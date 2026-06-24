//
//  KotlinNativeSwift2KotlinGenerator.swift
//  swift-java
//
//  Generates Kotlin/Native sources that call the Swift `@_cdecl` C thunks
//  directly via cinterop, with no JVM / Java FFM layer in between.
//
//  This generator emits two artifacts from a single resolved model:
//   1. `<Module>.kt`  — Kotlin/Native wrappers that call the cinterop-bound
//      thunk functions (imported via a wildcard import of the cinterop package).
//   2. `<Module>.h`   — a plain-C header declaring the thunks, which the
//      cinterop `.def` consumes. We emit our own clean header rather than the
//      SwiftPM-generated `<Module>-Swift.h` because the latter wraps the
//      thunks in `#pragma clang attribute push(external_source_symbol(
//      language="Swift", ...))`, which makes cinterop treat them as Swift
//      (not C) declarations and skip them.
//
//  Both artifacts are rendered from the same `[ResolvedFunc]` (see
//  `resolvedFunctions()`), so they always agree on which functions are emitted
//  and on the thunk symbol names.
//
//  Scope: Int/Int32/Bool/Double/Void, plus String *parameters* (passed as a
//  null-terminated UTF-8 C string via `String.cstr`, matching the thunk's
//  `String(cString:)`). String *returns* are still skipped (the thunk returns a
//  heap pointer the caller must free). Everything else is skipped with a comment.
//
import CodePrinting
import SwiftJavaConfigurationShared
import SwiftSyntax
import SwiftSyntaxBuilder
import Foundation

package class KotlinNativeSwift2KotlinGenerator {
  let log: Logger
  let config: Configuration
  let analysis: AnalysisResult
  let swiftModuleName: String
  let kotlinPackage: String
  let kotlinOutputDirectory: String
  let cinteropHeaderDirectory: String

  /// Source file paths registered with the translator; used to derive the
  /// expected SwiftPM plugin output file names for `--write-empty-files`.
  let translatorInputs: [SwiftJavaInputFile]

  /// Symbol table used to lower Swift signatures to their `@_cdecl` C form
  /// (e.g. `String` parameter -> `UnsafePointer<Int8>`).
  let symbolTable: SwiftSymbolTable

  /// Reuse the same thunk-naming as the FFM generator so the Kotlin calls
  /// resolve to the exact C symbols exported by the Swift `@_cdecl` thunks.
  var thunkNames: ThunkNameRegistry

  /// Cached result of resolving the imported global functions into the model
  /// both renderers consume. Computed once (the resolution mutates
  /// `thunkNames`); see `resolvedFunctions()`.
  private var resolvedCache: [ResolvedFunc]?

  /// A top-level function that maps cleanly onto a single `@_cdecl` thunk.
  struct NativeFunc {
    let kotlinName: String       // e.g. "add"
    let thunkName: String        // e.g. "swiftjava_SimpleSwiftLib_add_a_b"
    let kotlinParams: [String]   // e.g. ["a: Long", "b: Long"]
    let kotlinReturn: KotlinType // e.g. .long
    /// Arguments passed to the thunk, with per-parameter conversion applied
    /// (primitives pass through; `String` becomes `name.cstr`;
    ///  `[UInt8]` expands to `pinned_name.addressOf(0), name.size.toLong()`).
    let callArgs: [String]
    let isThrowing: Bool
    /// True if any argument needs a `kotlinx.cinterop` conversion (e.g. `.cstr`).
    let usesCInterop: Bool
    /// The thunk's C declaration, lowered via the shared FFM CType/CFunction
    /// machinery — the same lowering that produces FFM's Java FunctionDescriptor,
    /// so the C ABI has a single source of truth across modes.
    let cFunction: CFunction
    /// One entry per parameter that must be pinned before calling the thunk.
    /// Non-empty means `printKotlinFunction` wraps the call in nested
    /// `usePinned { }` blocks.
    let pinnings: [Pinning]

    /// Describes a parameter that needs `usePinned` at the call site.
    struct Pinning {
      let paramName: String    // e.g. "data"
      let pinnedName: String   // e.g. "pinned_data"
    }
  }

  /// Outcome of resolving one imported function: either an emittable
  /// `NativeFunc`, or a `// Skipped …` comment explaining why it was dropped.
  enum ResolvedFunc {
    case emit(NativeFunc)
    case skip(comment: String)
  }

  /// Package that cinterop generates its bindings into (set via the `.def`
  /// `package =` line). Wrappers wildcard-import this package.
  var cinteropPackage: String {
    kotlinPackage.isEmpty ? "cinterop" : "\(kotlinPackage).cinterop"
  }

  package init(config: Configuration, translator: Swift2JavaTranslator,
               kotlinPackage: String, kotlinOutputDirectory: String,
               cinteropHeaderDirectory: String) {
    self.log = Logger(label: "kotlin-native-generator", logLevel: translator.log.logLevel)
    self.config = config
    self.analysis = translator.result               // same IR as FFM / Kotlin-JVM generators
    self.swiftModuleName = translator.swiftModuleName
    self.kotlinPackage = kotlinPackage
    self.kotlinOutputDirectory = kotlinOutputDirectory
    self.cinteropHeaderDirectory = cinteropHeaderDirectory
    self.translatorInputs = translator.inputs
    self.symbolTable = translator.symbolTable
    self.thunkNames = ThunkNameRegistry()
  }

  func generate() throws {
    var printer = CodePrinter()
    try writeExportedKotlinSources(printer: &printer)

    var headerPrinter = CodePrinter()
    try writeCinteropHeader(printer: &headerPrinter)

    try writeSwiftThunkSourcesToDisk()
    try writeExpectedEmptySwiftSources()
  }

  // MARK: - Resolution (single source of truth for both artifacts)

  /// Resolve the module's top-level functions once. The result drives both the
  /// Kotlin and C-header renderers, guaranteeing they emit the same function
  /// set with the same thunk names.
  func resolvedFunctions() -> [ResolvedFunc] {
    if let cached = resolvedCache { return cached }
    let resolved = analysis.importedGlobalFuncs.map { resolve($0) }
    resolvedCache = resolved
    return resolved
  }

  private func resolve(_ decl: ImportedFunc) -> ResolvedFunc {
    func skip(_ reason: String) -> ResolvedFunc {
      .skip(comment: "// Skipped \(decl.displayName): \(reason)")
    }

    // Only top-level functions: skip members/initializers/accessors/etc.
    guard decl.apiKind == .function else { return skip("apiKind=\(decl.apiKind)") }
    guard decl.hasParent == false else { return skip("not a top-level function (has parent)") }
    guard decl.isAsync == false else { return skip("async not supported in kotlinNative mode") }

    // Kotlin-side scope gate. Supported parameter types: Int/Int32/Bool/Double,
    // String (passed as a null-terminated UTF-8 C string via `.cstr`), and
    // [UInt8] (passed as a pinned ByteArray pointer + count pair).
    var kotlinParams: [String] = []
    var callArgs: [String] = []
    var usesCInterop = false
    var pinnings: [NativeFunc.Pinning] = []
    for (i, p) in decl.functionSignature.parameters.enumerated() {
      guard let ktTy = swiftTypeToKotlin(p.type) else {
        return skip("unsupported param type '\(p.type)'")
      }
      let name = parameterName(p, at: i)
      kotlinParams.append("\(name): \(ktTy)")
      switch ktTy {
      case .string:
        // The thunk takes `UnsafePointer<Int8>` and does `String(cString:)`;
        // `.cstr` yields a null-terminated UTF-8 buffer that cinterop pins for
        // the duration of the call.
        callArgs.append("\(name).cstr")
        usesCInterop = true
      case .array:
        // [UInt8] is lowered to (pointer, count) in the C thunk. Pin the
        // ByteArray and pass the base address + length.
        let pinnedName = "pinned_\(name)"
        pinnings.append(NativeFunc.Pinning(paramName: name, pinnedName: pinnedName))
        callArgs.append("\(pinnedName).addressOf(0)")
        callArgs.append("\(name).size.toLong()")
        usesCInterop = true
      default:
        callArgs.append(name)
      }
    }

    // Return type. String and [UInt8] returns are supported.
    let ktReturnType = swiftTypeToKotlin(decl.functionSignature.result.type)
    guard let ktReturn = ktReturnType else {
      return skip("unsupported return type '\(decl.functionSignature.result.type)'")
    }

    // C-side: lower the Swift signature to its `@_cdecl` form via the shared FFM
    // lowering, then render the C declaration. For `[UInt8]` returns we use a
    // KN-specific ABI (`uint8_t* thunk(..., ptrdiff_t* result_count)`) because
    // the FFM callback ABI is incompatible with Kotlin/Native's staticCFunction.
    let thunkName = thunkNames.functionThunkName(decl: decl)
    let cFunction: CFunction
    do {
      let lowered = try CdeclLowering(symbolTable: symbolTable)
        .lowerFunctionSignature(decl.functionSignature)
      switch ktReturn {
      case .array(.uByte):
        // Append the out-count arg that the Kotlin wrapper will pass via memScoped.
        callArgs.append("countVar.ptr")
        let knownTypes = SwiftKnownTypes(symbolTable: symbolTable)
        let normalParams = lowered.parameters.flatMap { $0.cdeclParameters }
        let countParam = SwiftParameter(
          convention: .byValue,
          parameterName: "result_count",
          type: knownTypes.unsafeMutablePointer(knownTypes.int)
        )
        let customSig = SwiftFunctionSignature(
          selfParameter: nil,
          parameters: normalParams + [countParam],
          result: SwiftResult(convention: .direct, type: knownTypes.unsafeMutablePointer(knownTypes.uint8)),
          effectSpecifiers: [],
          genericParameters: [],
          genericRequirements: []
        )
        cFunction = try CFunction(cdeclSignature: customSig, cName: thunkName)
      default:
        cFunction = try CFunction(cdeclSignature: lowered.cdeclSignature, cName: thunkName)
      }
    } catch {
      return skip("unsupported C lowering: \(error)")
    }

    return .emit(NativeFunc(
      kotlinName: decl.name,
      thunkName: thunkName,
      kotlinParams: kotlinParams,
      kotlinReturn: ktReturn,
      callArgs: callArgs,
      isThrowing: decl.isThrowing,
      usesCInterop: usesCInterop,
      cFunction: cFunction,
      pinnings: pinnings
    ))
  }

  // MARK: - Kotlin sources

  package func writeExportedKotlinSources(printer: inout CodePrinter) throws {
    let filename = "\(swiftModuleName).kt"
    printKotlinModuleFile(&printer)
    _ = try printer.writeContents(
      outputDirectory: kotlinOutputDirectory,
      javaPackagePath: kotlinPackage.replacingOccurrences(of: ".", with: "/"),
      filename: filename
    )
  }

  func printKotlinModuleFile(_ printer: inout CodePrinter) {
    printer.print("// Generated by jextract-swift (kotlinNative mode)")
    printer.print("// Swift module: \(swiftModuleName)")
    printer.print("// Calls Swift @_cdecl C thunks directly via Kotlin/Native cinterop\n")
    printer.print("package \(kotlinPackage)\n")
    printer.print("import \(cinteropPackage).*")

    printer.print("import kotlinx.cinterop.*")
    // `free` is needed to release heap-allocated pointers returned by
    // String- and [UInt8]-returning thunks; it is NOT in kotlinx.cinterop.
    let needsFree = resolvedFunctions().contains {
      if case .emit(let fn) = $0 {
        return fn.kotlinReturn == .string || fn.kotlinReturn == .array(.uByte)
      }
      return false
    }
    if needsFree {
      printer.print("import platform.posix.free")
    }
    printer.print("")

    for resolved in resolvedFunctions() {
      switch resolved {
      case .skip(let comment):
        printer.print(comment)
      case .emit(let fn):
        printKotlinFunction(&printer, fn)
      }
      printer.print("")
    }
  }

  func printKotlinFunction(_ printer: inout CodePrinter, _ fn: NativeFunc) {
    let paramsString = fn.kotlinParams.joined(separator: ", ")
    let throwsComment = fn.isThrowing ? " // throws" : ""
    let argsString = fn.callArgs.joined(separator: ", ")

    printer.print("fun \(fn.kotlinName)(\(paramsString)): \(fn.kotlinReturn) {\(throwsComment)")
    // One or more ByteArray parameters: wrap the call in nested usePinned
    // blocks so the GC cannot move the arrays while the thunk is running.
    var indent = "  "
    for (i, pinning) in fn.pinnings.enumerated() {
      // Only the outermost usePinned needs a `return` prefix (for non-Unit
      // returns) because usePinned is inline and propagates the lambda value.
      let returnPrefix = (i == 0 && fn.kotlinReturn != .unit) ? "return " : ""
      printer.print("\(indent)\(returnPrefix)\(pinning.paramName).usePinned { \(pinning.pinnedName) ->")
      indent += "  "
    }
    let returnPrefix = (fn.pinnings.isEmpty) ? "return " : ""
    switch fn.kotlinReturn {
    case .unit:
      printer.print("\(indent)\(fn.thunkName)(\(argsString))")
    case .string:
      // `return ""` is a non-local return from the enclosing named function,
      // which is valid because usePinned is an inline function.
      printer.print("\(indent)val ptr = \(fn.thunkName)(\(argsString)) ?: return \"\"")
      printer.print("\(indent)val result = ptr.toKString()")
      printer.print("\(indent)free(ptr)")
      printer.print("\(indent)\(returnPrefix)result")
    case .array(.uByte):
      // The thunk returns a heap-allocated uint8_t* (caller must free) plus
      // writes the element count into result_count. memScoped allocates the
      // count variable on the stack; it is an inline function, so non-local
      // `return` is valid inside its lambda.
      printer.print("\(indent)memScoped {")
      let ms = indent + "  "
      printer.print("\(ms)val countVar = alloc<LongVar>()")
      // `return UByteArray(0)` is a non-local return valid because both
      // memScoped and usePinned are inline functions.
      printer.print("\(ms)val ptr = \(fn.thunkName)(\(argsString)) ?: return UByteArray(0)")
      printer.print("\(ms)val count = countVar.value.convert<Int>()")
      printer.print("\(ms)val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()")
      printer.print("\(ms)free(ptr)")
      // With pinnings the `return` on the outer usePinned propagates the value;
      // bare `result` is the last expression of the memScoped lambda.
      // Without pinnings we need an explicit `return result`.
      printer.print("\(ms)\(returnPrefix)result")
      printer.print("\(indent)}")
    default:
      // The expression value propagates out through each usePinned lambda.
      printer.print("\(indent)\(returnPrefix)\(fn.thunkName)(\(argsString))")
    }
    // Close the usePinned blocks in reverse order.
    for _ in fn.pinnings {
      indent = String(indent.dropLast(2))
      printer.print("\(indent)}")
    }
    printer.print("}")
  }

  // MARK: - cinterop C header

  func writeCinteropHeader(printer: inout CodePrinter) throws {
    let guardName = "\(swiftModuleName.uppercased())_CINTEROP_H"
    printer.print("// Generated by jextract-swift (kotlinNative mode)")
    printer.print("// Plain-C declarations of the Swift @_cdecl thunks for Kotlin/Native cinterop.")
    printer.print("#ifndef \(guardName)")
    printer.print("#define \(guardName)")
    printer.print("")
    // The lowered C types use the <stdint.h>/<stddef.h> typedefs
    // (ptrdiff_t, int32_t, ...) rather than bare int/long.
    printer.print("#include <stddef.h>")
    printer.print("#include <stdint.h>")
    printer.print("")
    for resolved in resolvedFunctions() {
      guard case .emit(let fn) = resolved else { continue }
      printer.print("\(fn.cFunction.description);")
    }
    printer.print("")
    printer.print("#endif")

    _ = try printer.writeContents(
      outputDirectory: cinteropHeaderDirectory,
      javaPackagePath: "",
      filename: "\(swiftModuleName).h"
    )
  }

  // MARK: - Type mapping

  /// Map a Swift known type to its Kotlin equivalent, or `nil` if unsupported.
  func swiftTypeToKotlin(_ t: SwiftType) -> KotlinType? {
    if case .nominal(let nominalType) = t,
      let known = nominalType.asKnownType {
        switch known {
        case .int: return .long
        case .int8: return .byte
        case .int16: return .short
        case .int32: return .int
        case .int64: return .long
        case .uint: return .uLong
        case .uint8: return .uByte
        case .uint16: return .uShort
        case .uint32: return .uInt
        case .uint64: return .uLong
        case .bool: return .boolean
        case .float: return .float
        case .double: return .double
        case .string: return .string
        case .void: return .unit
        case .array(let element):
          // Only [UInt8] is supported: it lowers to a (const void*, ptrdiff_t)
          // pair in the C thunk, which we wrap with usePinned on the Kotlin side.
          if let inner = swiftTypeToKotlin(element), inner == .uByte {
            return .array(.uByte)
          }
          return nil
        default: break
        }
    }

    switch String(describing: t) {
    case "Int", "Swift.Int": return .long
    case "Int8", "Swift.Int8": return .byte
    case "Int16", "Swift.Int16": return .short
    case "Int32", "Swift.Int32": return .int
    case "Int64",  "Swift.Int64":  return .long
    case "UInt",   "Swift.UInt":   return .uLong
    case "UInt8",  "Swift.UInt8":  return .uByte
    case "UInt16", "Swift.UInt16": return .uShort
    case "UInt32", "Swift.UInt32": return .uInt
    case "UInt64", "Swift.UInt64": return .uLong
    case "Bool",   "Swift.Bool":   return .boolean
    case "Float",  "Swift.Float":  return .float
    case "Double", "Swift.Double": return .double
    case "String", "Swift.String": return .string
    case "Void",   "Swift.Void", "()": return .unit
    case "[UInt8]", "[Swift.UInt8]": return .array(.uByte)
    default: return nil
    }
  }

  /// Resolve a Kotlin-safe parameter name: use the Swift parameter name,
  /// synthesize `p0`/`p1`/... when absent, and backtick-escape keywords.
  func parameterName(_ p: SwiftParameter, at index: Int) -> String {
    var name = (p.parameterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    if name.isEmpty || name == "_" {
      name = "p\(index)"
    }
    let kotlinKeywords: Set<String> = [
      "object", "class", "fun", "val", "var", "when", "is", "in",
      "as", "try", "catch", "finally", "null", "true", "false",
    ]
    return kotlinKeywords.contains(name) ? "`\(name)`" : name
  }
}
