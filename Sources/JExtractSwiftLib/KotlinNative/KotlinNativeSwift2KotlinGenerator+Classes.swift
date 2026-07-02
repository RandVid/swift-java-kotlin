//
//  KotlinNativeSwift2KotlinGenerator+Classes.swift
//  swift-java
//
//  Emits Kotlin/Native wrapper classes for imported Swift nominal types
//  (class & struct). Each wrapper holds a `SwiftHandle` — an opaque
//  `COpaquePointer` to a Swift-allocated box — and calls the `@_cdecl` thunks
//  via cinterop. Lifetime follows the "Option B" model from `.claude/ClassImpl.md`:
//  the Swift thunk allocates the box and returns the pointer; cleanup runs the
//  per-type `_destroy` thunk exactly once (via `close()` or a GC `createCleaner`).
//
//  Supported members: initializers, instance methods, static methods, and
//  stored-property get/set. Supported member parameter/return types: all
//  primitives, Bool, Float, Double, String, optional primitives/strings, custom
//  objects, and `[UInt8]`/`UByteArray`. Enums, protocols, generics, subscripts,
//  async, and throwing members are skipped with a comment.
//
import CodePrinting
import SwiftSyntax

extension KotlinNativeSwift2KotlinGenerator {

  // MARK: - Member support gate (single source of truth for Kotlin + Swift sides)

  /// Whether a wrapper member can be emitted. Both the Kotlin wrapper and the
  /// Swift `@_cdecl` thunk consult this so the two artifacts always agree on the
  /// emitted symbol set. Supports all primitives, `String`, optionals of those,
  /// `[UInt8]`, and custom imported types as parameter/return types.
  func memberIsEmittable(_ decl: ImportedFunc) -> Bool {
    switch decl.apiKind {
    case .function, .initializer, .getter, .setter: break
    default: return false
    }
    if decl.isAsync { return false }
    // Throwing members are not supported (the Kotlin call site cannot pass the
    // `result$throws` error-out pointer the thunk expects), so skip them entirely.
    if decl.isThrowing { return false }
    guard let ret = swiftTypeToKotlin(decl.functionSignature.result.type) else {
      return false
    }
    for p in decl.functionSignature.parameters {
      guard swiftTypeToKotlin(p.type) != nil else { return false }
    }
    // Final gate: the signature must be lowerable to a C `@_cdecl` thunk. Some
    // signatures map type-by-type via `swiftTypeToKotlin` yet still fail lowering
    // (e.g. an `inout` parameter). Attempting the lowering here keeps the Kotlin
    // wrapper, the C header, and the Swift thunk in lockstep: if it throws, all
    // three skip the member rather than the Kotlin side emitting a call to a
    // symbol the header/thunk never produced.
    // Mirror the stripping that loweredCdeclForThunk applies before CdeclLowering:
    //   • String? params → String  (CdeclLowering can't lower Optional<String>)
    //   • Optional returns → wrapped type (custom KN ABI: heap T*; null = absent)
    //   • [UInt8] array returns → Void  (custom KN ABI: heap UInt8* + out-count)
    let knownTypes = SwiftKnownTypes(symbolTable: symbolTable)
    let strippedParams = decl.functionSignature.parameters.map { p -> SwiftParameter in
      guard isOptionalString(p.type) else { return p }
      return SwiftParameter(convention: p.convention, argumentLabel: p.argumentLabel,
                            parameterName: p.parameterName, type: knownTypes.string)
    }
    let strippedResult: SwiftResult = {
      if ret == .array(.uByte) { return SwiftResult(convention: .direct, type: .void) }
      if let wrapped = extractOptionalWrappedType(decl.functionSignature.result.type) {
        return SwiftResult(convention: decl.functionSignature.result.convention, type: wrapped)
      }
      return decl.functionSignature.result
    }()
    let checkSig = SwiftFunctionSignature(
      selfParameter: decl.functionSignature.selfParameter,
      parameters: strippedParams,
      result: strippedResult,
      effectSpecifiers: decl.functionSignature.effectSpecifiers,
      genericParameters: decl.functionSignature.genericParameters,
      genericRequirements: decl.functionSignature.genericRequirements
    )
    do {
      _ = try CdeclLowering(symbolTable: symbolTable).lowerFunctionSignature(checkSig)
    } catch {
      return false
    }
    return true
  }

  // MARK: - Wrapper class

  func printKotlinClass(_ printer: inout CodePrinter, _ nominal: ImportedNominalType) {
    // Use the flat (qualified, `_`-joined) name as the Kotlin class identity so
    // it is unique across nested/same-simple-name types and matches the member
    // thunk symbols and the `_destroy` thunk.
    let className = nominal.swiftNominal.flatName

    switch nominal.swiftNominal.kind {
    case .class:
      break
    case .struct:
      printer.print("// Structs are forbidden for now")
    case .actor, .enum, .protocol:
      printer.print("// Skipped \(className): only class/struct are supported in kotlinNative mode")
      return
    }

    let destroy = destroyThunkName(className)

    printer.print("@OptIn(ExperimentalNativeApi::class)")
    printer.print("class \(className) internal constructor(private val __obj: NSObject) {")
    // GC fallback: the lambda captures only `__handle` (passed as the cleaner's
    // root), never `this`, so the cleaner can actually run.
//    printer.print("  private val __cleaner = createCleaner(__handle) { it.destroy() }")
    printer.print("  internal fun __ptr(): COpaquePointer = interpretCPointer<CPointed>(__obj.objcPtr())!!")
//    printer.print("  override fun close() = __handle.destroy()")

    // Constructors (Swift initializers).
    for initializer in nominal.initializers {
      guard memberIsEmittable(initializer) else {
        printer.print("  // Skipped \(initializer.displayName): unsupported signature for a kotlinNative member")
        continue
      }
      for line in renderConstructor(initializer, className: className, destroy: destroy) {
        printer.print(line)
      }
    }

    // Instance methods.
    for method in nominal.methods where !method.isStatic {
      guard memberIsEmittable(method) else {
        printer.print("  // Skipped \(method.displayName): unsupported signature for a kotlinNative member")
        continue
      }
      for line in renderMethod(method, isStatic: false) {
        printer.print(line)
      }
    }

    // Properties (paired getter/setter), restricted to emittable accessors.
    for line in renderProperties(nominal.variables.filter(memberIsEmittable)) {
      printer.print(line)
    }

    // Static methods live in the companion object.
    let staticMethods = nominal.methods.filter { $0.isStatic && memberIsEmittable($0) }
    if !staticMethods.isEmpty {
      printer.print("  companion object {")
      for method in staticMethods {
        for line in renderMethod(method, isStatic: true) {
          printer.print("  \(line)")
        }
      }
      printer.print("  }")
    }

    printer.print("}")
  }

  // MARK: - Member rendering

  private func renderConstructor(_ decl: ImportedFunc, className: String, destroy: String) -> [String] {
    var paramDecls: [String] = []
    var args: [String] = []
    var pinnings: [(paramName: String, pinnedName: String)] = []

    for (i, p) in decl.functionSignature.parameters.enumerated() {
      guard let pa = kotlinParamAndArg(p, name: parameterName(p, at: i)) else {
        return ["  // Skipped \(decl.displayName): unsupported parameter type '\(p.type)'"]
      }
      paramDecls.append(pa.param)
      args.append(contentsOf: pa.callArgs)
      if let pinning = pa.pinning { pinnings.append(pinning) }
    }

    let thunk = cinteropName(nativeThunkName(decl: decl))
      // `wrapSwiftObject` runs the thunk + `interpretObjCPointer` inside an
      // `autoreleasepool` so the thunk's `passRetained(...).autorelease()` +1 is
      // balanced (see `printObjectWrapHelper`).
      var expr = "wrapSwiftObject { \(thunk)(\(args.joined(separator: ", "))) }"
    for pinning in pinnings.reversed() {
      expr = "\(pinning.paramName).usePinned { \(pinning.pinnedName) -> \(expr) }"
    }
    return ["  constructor(\(paramDecls.joined(separator: ", "))) : this(\(expr))"]
  }

  /// Render an instance or static method as a Kotlin function.
  private func renderMethod(_ decl: ImportedFunc, isStatic: Bool) -> [String] {
    guard decl.apiKind == .function else {
      return ["  // Skipped \(decl.displayName): \(decl.apiKind) not supported as a method"]
    }
    guard decl.isAsync == false else {
      return ["  // Skipped \(decl.displayName): async not supported in kotlinNative mode"]
    }
    guard let ret = swiftTypeToKotlin(decl.functionSignature.result.type) else {
      return ["  // Skipped \(decl.displayName): unsupported return type '\(decl.functionSignature.result.type)'"]
    }

    var paramDecls: [String] = []
    var args: [String] = []
    var pinnings: [(paramName: String, pinnedName: String)] = []

    for (i, p) in decl.functionSignature.parameters.enumerated() {
      guard let pa = kotlinParamAndArg(p, name: parameterName(p, at: i)) else {
        return ["  // Skipped \(decl.displayName): unsupported parameter type '\(p.type)'"]
      }
      paramDecls.append(pa.param)
      args.append(contentsOf: pa.callArgs)
      if let pinning = pa.pinning { pinnings.append(pinning) }
    }

    // [UInt8] array returns pass an out-count pointer to the thunk before self.
    if case .array = ret {
      args.append("countVar.ptr")
    }
    // Instance methods pass `self` (the box pointer) last.
    if !isStatic {
      args.append("__ptr()")
    }

    let thunk = cinteropName(nativeThunkName(decl: decl))
    let callExpr = "\(thunk)(\(args.joined(separator: ", ")))"
    var lines: [String] = []
    lines.append("  fun \(decl.name)(\(paramDecls.joined(separator: ", "))): \(ret) {")
    lines += renderFunctionBody(callExpr: callExpr, ret: ret, pinnings: pinnings, baseIndent: "    ")
    lines.append("  }")
    return lines
  }

  /// Render Kotlin properties from the variable getters/setters of a type.
  private func renderProperties(_ variables: [ImportedFunc]) -> [String] {
    // Preserve declaration order while pairing getter+setter by property name.
    var order: [String] = []
    var getters: [String: ImportedFunc] = [:]
    var setters: [String: ImportedFunc] = [:]
    for v in variables {
      switch v.apiKind {
      case .getter:
        if getters[v.name] == nil { order.append(v.name) }
        getters[v.name] = v
      case .setter:
        setters[v.name] = v
      default:
        continue
      }
    }

    var lines: [String] = []
    for name in order {
      guard let getter = getters[name] else { continue }
      guard let ret = swiftTypeToKotlin(getter.functionSignature.result.type) else {
        lines.append("  // Skipped property \(name): unsupported type '\(getter.functionSignature.result.type)'")
        continue
      }
      let setter = setters[name]

      // Resolve setter param (if any) through kotlinParamAndArg so array params
      // get pinning metadata and all other types get their call-site expression.
      var setterPA: (param: String, callArgs: [String], pinning: (paramName: String, pinnedName: String)?)? = nil
      if let setter, let p = setter.functionSignature.parameters.first {
        guard let pa = kotlinParamAndArg(p, name: "value") else {
          lines.append("  // Skipped property \(name) setter: unsupported type '\(p.type)'")
          continue
        }
        setterPA = pa
      }

      let keyword = setterPA != nil ? "var" : "val"
      lines.append("  \(keyword) \(name): \(ret)")
      let getterThunk = cinteropName(nativeThunkName(decl: getter))
      let setterThunk = setterPA != nil ? cinteropName(nativeThunkName(decl: setter!)) : nil
      lines += renderPropertyAccessorLines(
        ret: ret,
        getterThunk: getterThunk,
        setterThunk: setterThunk,
        setterPA: setterPA,
        selfArgs: ["__ptr()"],
        blockIndent: "    ",
        bodyIndent: "      "
      )
    }
    return lines
  }

}
