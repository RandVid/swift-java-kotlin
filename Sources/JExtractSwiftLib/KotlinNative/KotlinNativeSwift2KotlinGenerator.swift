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
//  Scope (primitive-only, like the `kotlin` JVM mode minus String, which on
//  Kotlin/Native needs explicit memScoped conversion — deferred):
//  Int/Int32/Bool/Double/Void. Everything else is skipped with a comment.
//
import CodePrinting
import SwiftJavaConfigurationShared
import SwiftSyntax
import SwiftSyntaxBuilder
import Foundation

package class KotlinNativeSwift2KotlinGenerator {
  let log: Logger
  let analysis: AnalysisResult
  let swiftModuleName: String
  let kotlinPackage: String
  let kotlinOutputDirectory: String
  let cinteropHeaderDirectory: String

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
    let kotlinReturn: String     // e.g. "Long"
    let argNames: [String]       // e.g. ["a", "b"] (Kotlin call arguments)
    let isThrowing: Bool
    /// The thunk's C declaration, lowered via the shared FFM CType/CFunction
    /// machinery — the same lowering that produces FFM's Java FunctionDescriptor,
    /// so the C ABI has a single source of truth across modes.
    let cFunction: CFunction
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
    self.analysis = translator.result               // same IR as FFM / Kotlin-JVM generators
    self.swiftModuleName = translator.swiftModuleName
    self.kotlinPackage = kotlinPackage
    self.kotlinOutputDirectory = kotlinOutputDirectory
    self.cinteropHeaderDirectory = cinteropHeaderDirectory
    self.thunkNames = ThunkNameRegistry()
  }

  func generate() throws {
    var printer = CodePrinter()
    try writeExportedKotlinSources(printer: &printer)

    var headerPrinter = CodePrinter()
    try writeCinteropHeader(printer: &headerPrinter)
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

    // Kotlin-side scope gate: defines what kotlinNative supports today
    // (Int/Int32/Bool/Double/Void). String is deferred (needs memScoped
    // conversion); everything else is unsupported.
    var kotlinParams: [String] = []
    var argNames: [String] = []
    for (i, p) in decl.functionSignature.parameters.enumerated() {
      let ktTy = swiftTypeToKotlin(p.type)
      if ktTy == "String" {
        return skip("String parameter not supported in kotlinNative mode")
      }
      guard let ktTy else {
        return skip("unsupported param type '\(p.type)'")
      }
      let name = parameterName(p, at: i)
      kotlinParams.append("\(name): \(ktTy)")
      argNames.append(name)
    }

    let ktReturnType = swiftTypeToKotlin(decl.functionSignature.result.type)
    if ktReturnType == "String" {
      return skip("String return type not supported in kotlinNative mode")
    }
    guard let ktReturn = ktReturnType else {
      return skip("unsupported return type '\(decl.functionSignature.result.type)'")
    }

    // C-side: reuse the shared FFM cdecl -> CType/CFunction lowering for the
    // thunk's C declaration. This is the single source of truth for the C ABI
    // (the same lowering FFM uses for its FunctionDescriptor) and is correct for
    // every type FFM supports, not just primitives. For the primitive scope
    // gated above the raw signature is already cdecl-valid, so this does not
    // throw; the catch defends against the scope widening (e.g. Phase 5).
    let thunkName = thunkNames.functionThunkName(decl: decl)
    let cFunction: CFunction
    do {
      cFunction = try CFunction(cdeclSignature: decl.functionSignature, cName: thunkName)
    } catch {
      return skip("unsupported C lowering: \(error)")
    }

    return .emit(NativeFunc(
      kotlinName: decl.name,
      thunkName: thunkName,
      kotlinParams: kotlinParams,
      kotlinReturn: ktReturn,
      argNames: argNames,
      isThrowing: decl.isThrowing,
      cFunction: cFunction
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
    printer.print("import \(cinteropPackage).*\n")

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
    let argsString = fn.argNames.joined(separator: ", ")

    printer.print("fun \(fn.kotlinName)(\(paramsString)): \(fn.kotlinReturn) {\(throwsComment)")
    if fn.kotlinReturn == "Unit" {
      printer.print("  \(fn.thunkName)(\(argsString))")
    } else {
      printer.print("  return \(fn.thunkName)(\(argsString))")
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
  func swiftTypeToKotlin(_ t: SwiftType) -> String? {
    if let known = t.asNominalTypeDeclaration?.knownTypeKind {
      switch known {
      case .int: return "Long"
      case .int32: return "Int"
      case .bool: return "Boolean"
      case .double: return "Double"
      case .string: return "String"
      case .void: return "Unit"
      default: break
      }
    }

    switch String(describing: t) {
    case "Int", "Swift.Int": return "Long"
    case "Int32", "Swift.Int32": return "Int"
    case "Bool", "Swift.Bool": return "Boolean"
    case "Double", "Swift.Double": return "Double"
    case "String", "Swift.String": return "String"
    case "Void", "Swift.Void", "()": return "Unit"
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
