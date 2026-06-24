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

  /// Cached result of resolving top-level global variable getters/setters.
  private var resolvedGlobalVarsCache: [NativeGlobalVar]?

  /// Global variable accessor decls (`apiKind == .getter/.setter`) that are
  /// emittable — filtered to exactly those whose variable name appears in
  /// `resolvedGlobalVariables()`. Both `writeCinteropHeader` and
  /// `writeSwiftThunkSources` iterate this so they always cover the same set.
  var emittableGlobalVarAccessors: [ImportedFunc] {
    let names = Set(resolvedGlobalVariables().map(\.name))
    return analysis.importedGlobalVariables.filter {
      ($0.apiKind == .getter || $0.apiKind == .setter)
      && !$0.hasParent
      && names.contains($0.name)
    }
  }

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

  /// A resolved top-level global variable (Swift stored/computed var) ready to
  /// emit as a Kotlin `val` (getter only) or `var` (getter + setter) property.
  struct NativeGlobalVar {
    let name: String
    let kotlinType: KotlinType
    let getterThunk: String       // already backtick-escaped via cinteropName
    let setterThunk: String?      // nil → val (read-only)
    /// Full `kotlinParamAndArg` result for the setter value parameter.
    /// Carries the call-site expression(s) and pinning info for all types,
    /// including `[UInt8]` (two args + usePinned) and optionals.
    let setterPA: (param: String, callArgs: [String], pinning: (paramName: String, pinnedName: String)?)?
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

  /// Fully-qualified names of the Swift nominal types (class/struct) imported
  /// from this module, for which we generate Kotlin wrapper classes. Matching on
  /// the qualified name (not the bare simple name) avoids mis-mapping a different
  /// type that merely shares a simple name (a nested type, or a same-named type
  /// from another module). Used by `swiftTypeToKotlin`.
  lazy var importedTypeQualifiedNames: Set<String> = {
    Set(analysis.importedTypes.values.map { $0.swiftNominal.qualifiedName })
  }()

  /// The C symbol name of the per-type `_destroy` thunk. The Kotlin wrapper
  /// passes this to `SwiftHandle` and the Swift side emits a matching `@_cdecl`.
  func destroyThunkName(_ typeName: String) -> String {
    "swiftjava_\(swiftModuleName)_\(typeName)_destroy"
  }

  /// The C symbol for a decl's thunk in kotlinNative mode.
  ///
  /// The shared `ThunkNameRegistry` appends `$get`/`$set` for accessors and `$N`
  /// for overload de-duplication. `$` is a valid character in Java/JNI symbols,
  /// but Kotlin/Native's cinterop lowers each symbol into a generated C bridge of
  /// the form `… __asm("<symbol>")`, and the compiler's file-lowering pass parses
  /// that C snippet treating `$…$` as a placeholder delimiter — a lone `$` makes it
  /// abort with "Bad code snippet, no closing '$' was found". So we replace `$`
  /// with `_` here and route the Swift `@_cdecl` name, the C header declaration,
  /// and the Kotlin cinterop reference all through this method, keeping the three
  /// artifacts in agreement on one `$`-free ABI symbol.
  func nativeThunkName(decl: ImportedFunc) -> String {
    thunkNames.functionThunkName(decl: decl).replacingOccurrences(of: "$", with: "_kn_")
  }

  /// Render a cinterop function symbol for use in generated Kotlin source.
  /// Symbols are already sanitized to a `$`-free form by `nativeThunkName`, so no
  /// backtick-escaping is required; this remains as a defensive guard in case a
  /// symbol ever reaches Kotlin source with a `$` (which Kotlin would otherwise
  /// parse as the start of a string template).
  func cinteropName(_ thunkName: String) -> String {
    thunkName.contains("$") ? "`\(thunkName)`" : thunkName
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

  /// Resolve top-level global variable getters/setters into `NativeGlobalVar`s.
  /// Supported types: primitives, Bool, Float, Double, String. Arrays/optionals
  /// and custom object types are excluded (no pinning/memScoped for getters; no
  /// box-allocating thunk for top-level property getters).
  func resolvedGlobalVariables() -> [NativeGlobalVar] {
    if let cached = resolvedGlobalVarsCache { return cached }

    var getters: [(String, ImportedFunc)] = []
    var setterMap: [String: ImportedFunc] = [:]

    for decl in analysis.importedGlobalVariables {
      guard decl.hasParent == false,
            decl.isAsync == false,
            decl.isThrowing == false else { continue }
      switch decl.apiKind {
      case .getter:
        guard swiftTypeToKotlin(decl.functionSignature.result.type) != nil else { continue }
        getters.append((decl.name, decl))
      case .setter:
        setterMap[decl.name] = decl
      default:
        continue
      }
    }

    var result: [NativeGlobalVar] = []
    for (name, getter) in getters {
      guard let kt = swiftTypeToKotlin(getter.functionSignature.result.type) else { continue }
      let getterThunk = cinteropName(nativeThunkName(decl: getter))

      var setterThunk: String? = nil
      var setterPA: (param: String, callArgs: [String], pinning: (paramName: String, pinnedName: String)?)? = nil
      if let setter = setterMap[name],
         let p = setter.functionSignature.parameters.first,
         let pa = kotlinParamAndArg(p, name: "value") {
        setterThunk = cinteropName(nativeThunkName(decl: setter))
        setterPA = pa
      }

      result.append(NativeGlobalVar(
        name: name,
        kotlinType: kt,
        getterThunk: getterThunk,
        setterThunk: setterThunk,
        setterPA: setterPA
      ))
    }

    resolvedGlobalVarsCache = result
    return result
  }

  private func resolve(_ decl: ImportedFunc) -> ResolvedFunc {
    func skip(_ reason: String) -> ResolvedFunc {
      .skip(comment: "// Skipped \(decl.displayName): \(reason)")
    }

    // Only top-level functions: skip members/initializers/accessors/etc.
    guard decl.apiKind == .function else { return skip("apiKind=\(decl.apiKind)") }
    guard decl.hasParent == false else { return skip("not a top-level function (has parent)") }
    guard decl.isAsync == false else { return skip("async not supported in kotlinNative mode") }
    // Throwing functions are not supported: the Kotlin call site does not pass
    // the `result$throws` error-out pointer the lowered thunk expects, so the
    // generated wrapper would not compile. Skip them on every artifact.
    guard decl.isThrowing == false else { return skip("throwing functions are not supported in kotlinNative mode") }

    var kotlinParams: [String] = []
    var callArgs: [String] = []
    var usesCInterop = false
    var pinnings: [NativeFunc.Pinning] = []
    for (i, p) in decl.functionSignature.parameters.enumerated() {
      let name = parameterName(p, at: i)
      guard let pa = kotlinParamAndArg(p, name: name) else {
        return skip("unsupported param type '\(p.type)'")
      }
      kotlinParams.append(pa.param)
      callArgs.append(contentsOf: pa.callArgs)
      if let pinning = pa.pinning {
        pinnings.append(NativeFunc.Pinning(paramName: pinning.paramName, pinnedName: pinning.pinnedName))
      }
      // usesCInterop: true whenever the argument was transformed from its bare name
      // (String → .cstr, array → usePinned, optional → .let {…}, object → .__ptr()).
      if !(pa.callArgs.count == 1 && pa.callArgs[0] == name) { usesCInterop = true }
    }

    // Return type. String and [UInt8] returns are supported.
    let ktReturnType = swiftTypeToKotlin(decl.functionSignature.result.type)
    guard let ktReturn = ktReturnType else {
      return skip("unsupported return type '\(decl.functionSignature.result.type)'")
    }

    // C-side: lower the Swift signature to its `@_cdecl` form (via the shared
    // `loweredCdeclForThunk`, which strips the parts CDeclLowering rejects). Most
    // returns use the lowered cdecl signature directly; `[UInt8]`, optional, and
    // custom-object returns need a KN-specific custom CFunction because the FFM C
    // ABI does not fit Kotlin/Native.
    let thunkName = nativeThunkName(decl: decl)
    let knownTypes = SwiftKnownTypes(symbolTable: symbolTable)
    let cFunction: CFunction
    do {
      let (lowered, optionalReturnWrapped) = try loweredCdeclForThunk(decl)
      switch ktReturn {
      case .array(.uByte):
        // Append the out-count arg that the Kotlin wrapper will pass via memScoped.
        callArgs.append("countVar.ptr")
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
      case .optional(.string):
        // String? uses same C ABI as non-optional String: heap-allocated int8_t*, null = nil.
        // The stripped-signature lowering already produces the correct int8_t* return type.
        cFunction = try CFunction(cdeclSignature: lowered.cdeclSignature, cName: thunkName)
      case .optional:
        // KN-specific ABI: thunk returns UnsafeMutablePointer<T>? (heap-allocated,
        // null = absent). CType treats optional(pointer) as the pointer itself
        // (CRepresentation.swift:34), so the C header gets `T*` (nullable by convention).
        guard let wrappedSwiftType = optionalReturnWrapped else {
          return skip("optional return type not extractable")
        }
        let normalParams = lowered.parameters.flatMap { $0.cdeclParameters }
        let customSig = SwiftFunctionSignature(
          selfParameter: nil,
          parameters: normalParams,
          result: SwiftResult(
            convention: .direct,
            type: knownTypes.optionalSugar(knownTypes.unsafeMutablePointer(wrappedSwiftType))
          ),
          effectSpecifiers: [],
          genericParameters: [],
          genericRequirements: []
        )
        cFunction = try CFunction(cdeclSignature: customSig, cName: thunkName)
      case .object:
        // The thunk box-allocates the result and returns it as an opaque `void*`.
        cFunction = try objectReturnCFunction(
          lowered: lowered,
          selfParameter: decl.functionSignature.selfParameter,
          thunkName: thunkName
        )
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
    printer.print("import platform.posix.free")

    // Imports needed by generated wrapper classes (handle lifetime management).
    if !analysis.importedTypes.isEmpty {
      printer.print("import org.swift.swiftkit.kn.SwiftHandle")
      printer.print("import kotlin.experimental.ExperimentalNativeApi")
      printer.print("import kotlin.native.ref.createCleaner")
      printer.print("")
    }
    printer.print("")
    
    // Wrapper classes for imported Swift nominal types (class / struct).
    for typeName in analysis.importedTypes.keys.sorted() {
      guard let nominal = analysis.importedTypes[typeName] else { continue }
      printKotlinClass(&printer, nominal)
      printer.print("")
    }

    for resolved in resolvedFunctions() {
      switch resolved {
      case .skip(let comment):
        printer.print(comment)
      case .emit(let fn):
        printKotlinFunction(&printer, fn)
      }
      printer.print("")
    }

    // Top-level global variables as Kotlin val/var properties.
    for globalVar in resolvedGlobalVariables() {
      printKotlinGlobalVar(&printer, globalVar)
      printer.print("")
    }
  }

  func printKotlinGlobalVar(_ printer: inout CodePrinter, _ v: NativeGlobalVar) {
    let keyword = v.setterThunk == nil ? "val" : "var"
    printer.print("\(keyword) \(v.name): \(v.kotlinType)")
    for line in renderPropertyAccessorLines(
      ret: v.kotlinType,
      getterThunk: v.getterThunk,
      setterThunk: v.setterThunk,
      setterPA: v.setterPA,
      selfArgs: [],
      blockIndent: "    ",
      bodyIndent: "        "
    ) {
      printer.print(line)
    }
  }

  /// Render `get() { … }` and optionally `set(value) { … }` blocks for a Kotlin
  /// property. Shared by member `renderProperties` (pass `selfArgs: ["__ptr()"]`)
  /// and top-level global-variable emission (pass `selfArgs: []`).
  func renderPropertyAccessorLines(
    ret: KotlinType,
    getterThunk: String,
    setterThunk: String?,
    setterPA: (param: String, callArgs: [String], pinning: (paramName: String, pinnedName: String)?)?,
    selfArgs: [String],
    blockIndent: String,
    bodyIndent: String
  ) -> [String] {
    var lines: [String] = []

    // Getter — for array returns, countVar.ptr is threaded in before self so
    // it lands inside the memScoped block where countVar is in scope.
    var getterCallArgParts = selfArgs
    if case .array = ret { getterCallArgParts = ["countVar.ptr"] + selfArgs }
    let getterCallExpr = "\(getterThunk)(\(getterCallArgParts.joined(separator: ", ")))"

    lines.append("\(blockIndent)get() {")
    if case .array(.uByte) = ret {
      lines += renderFunctionBody(callExpr: getterCallExpr, ret: ret, pinnings: [], baseIndent: bodyIndent)
    } else {
      lines += returnBodyLines(callExpr: getterCallExpr, ret: ret, indent: bodyIndent, finalPrefix: "return ")
    }
    lines.append("\(blockIndent)}")

    // Setter
    if let setterThunk, let setterPA {
      let callStr = (setterPA.callArgs + selfArgs).joined(separator: ", ")
      lines.append("\(blockIndent)set(value) {")
      if let pinning = setterPA.pinning {
        lines.append("\(bodyIndent)\(pinning.paramName).usePinned { \(pinning.pinnedName) ->")
        lines.append("\(bodyIndent)  \(setterThunk)(\(callStr))")
        lines.append("\(bodyIndent)}")
      } else {
        lines.append("\(bodyIndent)\(setterThunk)(\(callStr))")
      }
      lines.append("\(blockIndent)}")
    }

    return lines
  }

  func printKotlinFunction(_ printer: inout CodePrinter, _ fn: NativeFunc) {
    let paramsString = fn.kotlinParams.joined(separator: ", ")
    let throwsComment = fn.isThrowing ? " // throws" : ""
    let callExpr = "\(cinteropName(fn.thunkName))(\(fn.callArgs.joined(separator: ", ")))"
    printer.print("fun \(fn.kotlinName)(\(paramsString)): \(fn.kotlinReturn) {\(throwsComment)")
    for line in renderFunctionBody(
      callExpr: callExpr, ret: fn.kotlinReturn,
      pinnings: fn.pinnings.map { ($0.paramName, $0.pinnedName) }, baseIndent: "  "
    ) {
      printer.print(line)
    }
    printer.print("}")
  }

  /// Render the body statements of a Kotlin function (excluding the outer braces).
  /// Handles `usePinned` wrapping for array params, `memScoped + out-count` for
  /// `[UInt8]` array returns, and delegates all other return types to
  /// `returnBodyLines`. Used by both `printKotlinFunction` (top-level) and
  /// `renderMethod` (class/struct members) so the two paths stay in lockstep.
  ///
  /// - Parameters:
  ///   - baseIndent: indent for the outermost body statement (e.g. `"  "` for
  ///     top-level, `"    "` for members inside a class body).
  ///   - pinnings: array parameters that need `usePinned` wrapping, in parameter
  ///     order.
  func renderFunctionBody(
    callExpr: String,
    ret: KotlinType,
    pinnings: [(paramName: String, pinnedName: String)],
    baseIndent: String
  ) -> [String] {
    var lines: [String] = []
    var indent = baseIndent

    for (i, pinning) in pinnings.enumerated() {
      // Only the outermost usePinned needs a `return` prefix (for non-Unit
      // returns) because usePinned is inline and propagates the lambda value.
      let returnPrefix = (i == 0 && ret != .unit) ? "return " : ""
      lines.append("\(indent)\(returnPrefix)\(pinning.paramName).usePinned { \(pinning.pinnedName) ->")
      indent += "  "
    }

    let finalPrefix = pinnings.isEmpty ? "return " : ""
    if case .array(.uByte) = ret {
      // The thunk returns a heap-allocated uint8_t* plus writes the element
      // count into result_count. memScoped allocates the count var on the stack;
      // it is inline, so a non-local `return` is valid in its lambda.
      lines.append("\(indent)memScoped {")
      let ms = indent + "  "
      lines.append("\(ms)val countVar = alloc<LongVar>()")
      lines.append("\(ms)val ptr = \(callExpr) ?: return UByteArray(0)")
      lines.append("\(ms)val count = countVar.value.convert<Int>()")
      lines.append("\(ms)val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()")
      lines.append("\(ms)free(ptr)")
      lines.append("\(ms)\(finalPrefix)result")
      lines.append("\(indent)}")
    } else {
      lines += returnBodyLines(callExpr: callExpr, ret: ret, indent: indent, finalPrefix: finalPrefix)
    }

    for _ in pinnings {
      indent = String(indent.dropLast(2))
      lines.append("\(indent)}")
    }
    return lines
  }

  /// Emit the Kotlin statements that turn a thunk-call expression into a return
  /// value, for all return kinds except `[UInt8]` arrays (handled by
  /// `renderFunctionBody`). `finalPrefix` is `"return "` normally, or `""` when
  /// the value is the last expression of an enclosing inline `usePinned` lambda
  /// that already carries the `return`.
  func returnBodyLines(callExpr: String, ret: KotlinType, indent: String, finalPrefix: String) -> [String] {
    switch ret {
    case .unit:
      return ["\(indent)\(callExpr)"]
    case .string, .optional(.string):
      // `return "" / null` is a non-local return, valid because any enclosing
      // usePinned/memScoped lambda is inline.
      let nilReturn = (ret == .string) ? "\"\"" : "null"
      return [
        "\(indent)val ptr = \(callExpr) ?: return \(nilReturn)",
        "\(indent)val result = ptr.toKString()",
        "\(indent)free(ptr)",
        "\(indent)\(finalPrefix)result",
      ]
    case .optional:
      // Heap-allocated T* (null = absent): dereference, copy, free.
      return [
        "\(indent)val ptr = \(callExpr) ?: return null",
        "\(indent)val result = ptr.pointed.value",
        "\(indent)free(ptr)",
        "\(indent)\(finalPrefix)result",
      ]
    case .object(let typeName):
      // Swift-allocated box pointer (void*, never null for a non-optional return):
      // wrap in the handle; cleanup runs the per-type `_destroy` thunk.
      return [
        "\(indent)val ptr = \(callExpr)",
        "\(indent)\(finalPrefix)\(typeName)(SwiftHandle(ptr!!, ::\(destroyThunkName(typeName))))",
      ]
    case .array:
      // [UInt8] array returns are handled by renderFunctionBody (memScoped path);
      // this case is never reached when called through that helper.
      return []
    default:
      return ["\(indent)\(finalPrefix)\(callExpr)"]
    }
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

    // C declarations for global variable getter/setter thunks.
    for decl in emittableGlobalVarAccessors {
      if let cFunction = try? memberCFunction(for: decl) {
        printer.print("\(cFunction.description);")
      }
    }

    // Declarations for nominal-type members and their `_destroy` thunks, so the
    // cinterop binding includes every symbol the wrapper classes call.
    for typeName in analysis.importedTypes.keys.sorted() {
      guard let nominal = analysis.importedTypes[typeName] else { continue }
      switch nominal.swiftNominal.kind {
      case .class, .struct: break
      default: continue
      }
      let members = nominal.initializers + nominal.methods + nominal.variables
      for decl in members where memberIsEmittable(decl) {
        if let cFunction = try? memberCFunction(for: decl) {
          printer.print("\(cFunction.description);")
        }
      }
      if let cFunction = try? destroyCFunction(for: nominal) {
        printer.print("\(cFunction.description);")
      }
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
        case .optional(let wrapped):
          guard let inner = swiftTypeToKotlin(wrapped) else { return nil }
          switch inner {
          case .long, .int, .short, .byte, .uLong, .uInt, .uShort, .uByte,
               .boolean, .float, .double, .string:
            return .optional(inner)
          default: return nil  // Optional<Array>, nested Optional not supported
          }
        default: break
        }
    }

    // Custom nominal types (class/struct) imported from this module map to their
    // generated Kotlin wrapper class. Match on the qualified name, and carry the
    // `flatName` (e.g. "Outer_Box") as the wrapper identity so it is unique and
    // matches the `_destroy` symbol and member thunk names (which also use it).
    if case .nominal(let nominalType) = t,
       nominalType.asKnownType == nil,
       importedTypeQualifiedNames.contains(nominalType.nominalTypeDecl.qualifiedName) {
      return .object(nominalType.nominalTypeDecl.flatName)
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

  /// Compute the Kotlin parameter declaration and thunk call-site arguments for
  /// a Swift parameter. For `[UInt8]` array params, `callArgs` contains two
  /// entries (base address + count) and `pinning` carries the names for the
  /// surrounding `usePinned` block; for all other types, `callArgs` has one
  /// entry and `pinning` is `nil`. Returns `nil` for unsupported types.
  func kotlinParamAndArg(
    _ p: SwiftParameter, name: String
  ) -> (param: String, callArgs: [String], pinning: (paramName: String, pinnedName: String)?)? {
    guard let kt = swiftTypeToKotlin(p.type) else { return nil }
    let param = "\(name): \(kt)"
    switch kt {
    case .string:
      return (param, ["\(name).cstr"], nil)
    case .optional(.string):
      return (param, ["\(name)?.cstr"], nil)
    case .optional(let inner):
      return (param, ["\(name)?.let { \(callArgForOptional(inner, value: "it")) }"], nil)
    case .object:
      return (param, ["\(name).__ptr()"], nil)
    case .array:
      let pinnedName = "pinned_\(name)"
      return (param, ["if (\(name).size > 0) \(pinnedName).addressOf(0) else null", "\(name).size.toLong()"],
              (paramName: name, pinnedName: pinnedName))
    default:
      return (param, [name], nil)
    }
  }

  /// Build the call-site expression that turns a non-null Kotlin nullable value
  /// into a C pointer for an optional parameter. For signed/float types, uses
  /// `cValuesOf(value)` which infers the Var type automatically. For unsigned
  /// types and Boolean, uses a single-element array with `refTo(0)` — also
  /// type-inferred, requiring no explicit Var name.
  func callArgForOptional(_ inner: KotlinType, value: String) -> String {
    switch inner {
    case .long, .int, .short, .byte, .float, .double:
      return "cValuesOf(\(value))"
    case .uLong:  return "ulongArrayOf(\(value)).refTo(0)"
    case .uInt:   return "uintArrayOf(\(value)).refTo(0)"
    case .uShort: return "ushortArrayOf(\(value)).refTo(0)"
    case .uByte:  return "ubyteArrayOf(\(value)).refTo(0)"
    case .boolean: return "booleanArrayOf(\(value)).refTo(0)"
    default: return "cValuesOf(\(value))"
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
