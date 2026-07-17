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
//  Supported members: initializers, instance methods, static methods,
//  stored-property get/set, and subscripts (`operator fun get`/`set`). Supported
//  member parameter/return types: all primitives, Bool, Float, Double, String, and
//  custom objects. Enums, protocols, generics, async, and throwing members are
//  skipped with a comment.
//
import CodePrinting
import SwiftSyntax

extension KotlinNativeSwift2KotlinGenerator {

  // MARK: - Member support gate (single source of truth for Kotlin + Swift sides)

  /// Whether a wrapper member can be emitted. Both the Kotlin wrapper and the
  /// Swift `@_cdecl` thunk consult this so the two artifacts always agree on the
  /// emitted symbol set. Supports all primitives, `String`, and custom imported
  /// types as parameter/return types.
  func memberIsEmittable(_ decl: ImportedFunc) -> Bool {
    switch decl.apiKind {
    case .function, .initializer, .getter, .setter, .subscriptGetter, .subscriptSetter: break
    default: return false
    }
    if decl.isAsync { return false }
    // Throwing members are not supported (the Kotlin call site cannot pass the
    // `result$throws` error-out pointer the thunk expects), so skip them entirely.
    if decl.isThrowing { return false }
    guard swiftTypeToKotlin(decl.functionSignature.result.type) != nil else {
      return false
    }
    for p in decl.functionSignature.parameters {
      guard swiftTypeToKotlin(p.type) != nil else { return false }
    }
    // Members that require mutable state — an `inout` parameter or a mutable
    // (`inout`) struct `self` (a `mutating` method or a struct property setter) —
    // use the bespoke `inout` thunk instead of the shared lowering (which rejects
    // `inout`). They are emittable iff that thunk's cdecl signature is supported.
    if needsInoutThunk(decl) {
      return (try? inoutCdeclSignature(for: decl)) != nil
    }
    // Final gate: the signature must be lowerable to a C `@_cdecl` thunk. Some
    // signatures map type-by-type via `swiftTypeToKotlin` yet still fail lowering.
    // Attempting the lowering here keeps the Kotlin wrapper, the C header, and the
    // Swift thunk in lockstep: if it throws, all three skip the member rather than
    // the Kotlin side emitting a call to a symbol the header/thunk never produced.
    do {
      _ = try CdeclLowering(symbolTable: symbolTable).lowerFunctionSignature(decl.functionSignature)
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
      // Structs use the two-class value-semantics model (immutable + Mutable).
      printKotlinStruct(&printer, nominal)
      return
    case .actor, .enum, .protocol:
      printer.print("// Skipped \(className): only class/struct are supported in kotlinNative mode")
      return
    }

    let destroy = destroyThunkName(className)

    // A class wrapper holds its box by reference; `__obj` is never reassigned (only
    // struct mutation re-boxes, and that lives on the `Inout<Struct>` extensions).
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
      let lines = needsInoutThunk(method) ? renderInoutMethod(method) : renderMethod(method, isStatic: false)
      for line in lines {
        printer.print(line)
      }
    }

    // Properties (paired getter/setter), restricted to emittable accessors.
    for line in renderProperties(nominal.variables.filter(memberIsEmittable)) {
      printer.print(line)
    }

    // Subscripts as `operator fun get`/`set`. On a class both accessors live on
    // the wrapper (reference `self`, so the setter is a plain member).
    for line in renderClassSubscripts(nominal.variables.filter(memberIsEmittable)) {
      printer.print(line)
    }

    // Static methods live in the companion object.
    let staticMethods = nominal.methods.filter { $0.isStatic && memberIsEmittable($0) }
    if !staticMethods.isEmpty {
      printer.print("  companion object {")
      for method in staticMethods {
        let lines = needsInoutThunk(method) ? renderInoutMethod(method, isStatic: true) : renderMethod(method, isStatic: true)
        for line in lines {
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

    for (i, p) in decl.functionSignature.parameters.enumerated() {
      guard let pa = kotlinParamAndArg(p, name: parameterName(p, at: i)) else {
        return ["  // Skipped \(decl.displayName): unsupported parameter type '\(p.type)'"]
      }
      paramDecls.append(pa.param)
      args.append(contentsOf: pa.callArgs)
    }

    let thunk = cinteropName(nativeThunkName(decl: decl))
    // `wrapSwiftObject` runs the thunk + `interpretObjCPointer` inside an
    // `autoreleasepool` so the thunk's `passRetained(...).autorelease()` +1 is
    // balanced (see `printObjectWrapHelper`).
    let expr = "wrapSwiftObject { \(thunk)(\(args.joined(separator: ", "))) }"
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

    for (i, p) in decl.functionSignature.parameters.enumerated() {
      guard let pa = kotlinParamAndArg(p, name: parameterName(p, at: i)) else {
        return ["  // Skipped \(decl.displayName): unsupported parameter type '\(p.type)'"]
      }
      paramDecls.append(pa.param)
      args.append(contentsOf: pa.callArgs)
    }

    // Instance methods pass `self` (the box pointer) last.
    if !isStatic {
      args.append("__ptr()")
    }

    let thunk = cinteropName(nativeThunkName(decl: decl))
    let callExpr = "\(thunk)(\(args.joined(separator: ", ")))"
    var lines: [String] = []
    lines.append("  fun \(decl.name)(\(paramDecls.joined(separator: ", "))): \(ret) {")
    lines += renderFunctionBody(callExpr: callExpr, ret: ret, baseIndent: "    ")
    lines.append("  }")
    return lines
  }

  /// Render a class instance/static method that has `inout` parameters. The body
  /// opens a `memScoped`, materializes each `inout` value into a native cell, calls
  /// the thunk, then copies the mutated cells back into the `Inout<T>` holders.
  /// (A class receiver is a shared reference, so `self` is the plain `__ptr()` box
  /// pointer — only structs have a mutable `inout` `self`, and those go through the
  /// `Inout<Struct>` extensions in `+Structs.swift`.)
  func renderInoutMethod(_ decl: ImportedFunc, isStatic: Bool = false) -> [String] {
    let ret = swiftTypeToKotlin(decl.functionSignature.result.type)!  // guaranteed by memberIsEmittable

    var paramDecls: [String] = []
    var callArgs: [String] = []
    var marshals: [InoutMarshal] = []

    for (i, p) in decl.functionSignature.parameters.enumerated() {
      let name = parameterName(p, at: i)
      if p.convention == .inout {
        let flavor = inoutFlavor(p.type)!
        let kt = swiftTypeToKotlin(p.type)!
        let cellVar = "\(name)_cell"
        paramDecls.append("\(name): Inout<\(kt)>")
        callArgs.append("\(cellVar).ptr")
        marshals.append(InoutMarshal(paramName: name, cellVar: cellVar, flavor: flavor))
      } else {
        let pa = kotlinParamAndArg(p, name: name)!
        paramDecls.append(pa.param)
        callArgs.append(contentsOf: pa.callArgs)
      }
    }
    if !isStatic {
      callArgs.append("__ptr()")
    }

    let thunk = cinteropName(nativeThunkName(decl: decl))
    let callExpr = "\(thunk)(\(callArgs.joined(separator: ", ")))"
    let isVoid = (ret == .unit)
    let outer = "    "
    let inner = "      "

    var lines: [String] = []
    lines.append("  fun \(decl.name)(\(paramDecls.joined(separator: ", "))): \(ret) {")
    lines.append("\(outer)\(isVoid ? "" : "return ")memScoped {")
    for m in marshals { lines += inoutCellPrologue(m, source: inoutRefSource(m), indent: inner) }
    if isVoid {
      lines.append("\(inner)\(callExpr)")
    } else {
      lines.append(inoutResultCapture(ret: ret, callExpr: callExpr, indent: inner))
    }
    for m in marshals { lines.append("\(inner)\(m.paramName).unsafeValue = \(inoutCellReadBack(m))") }
    if !isVoid { lines.append("\(inner)_result") }
    lines.append("\(outer)}")
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

      // Resolve setter param (if any) through kotlinParamAndArg to get its
      // call-site expression.
      var setterPA: (param: String, callArgs: [String])? = nil
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

      // A class property has reference semantics: the setter mutates through the box
      // pointer directly (`setter(value, __ptr())`), no re-box/swap. (Struct stored
      // properties are `Inout<Struct>` extensions in `+Structs.swift`.)
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

  // MARK: - Subscripts

  /// A subscript getter paired with its optional setter (matched by index-parameter
  /// type list). Shared by the class and struct wrapper emitters.
  struct SubscriptPair {
    let getter: ImportedFunc
    let setter: ImportedFunc?
  }

  /// Pair each `.subscriptGetter` in `variables` with its `.subscriptSetter`
  /// (matched on the index parameter types — the setter's params minus its trailing
  /// `newValue`). A read-only subscript has `setter == nil`.
  func subscriptPairs(_ variables: [ImportedFunc]) -> [SubscriptPair] {
    let getters = variables.filter { $0.apiKind == .subscriptGetter }
    var setters = variables.filter { $0.apiKind == .subscriptSetter }

    func indexTypes(_ decl: ImportedFunc, dropLast: Bool) -> [String] {
      var params = decl.functionSignature.parameters
      if dropLast, !params.isEmpty { params.removeLast() }
      return params.map { "\($0.type)" }
    }

    return getters.map { getter in
      let want = indexTypes(getter, dropLast: false)
      if let idx = setters.firstIndex(where: { indexTypes($0, dropLast: true) == want }) {
        let setter = setters.remove(at: idx)
        return SubscriptPair(getter: getter, setter: setter)
      }
      return SubscriptPair(getter: getter, setter: nil)
    }
  }

  /// Render class subscripts as `operator fun get`/`operator fun set` members. On a
  /// class (reference `self`) both accessors are plain members; `self` (`__ptr()`)
  /// is passed last, exactly like `renderMethod`.
  private func renderClassSubscripts(_ variables: [ImportedFunc]) -> [String] {
    var lines: [String] = []
    for pair in subscriptPairs(variables) {
      let getter = pair.getter
      guard let ret = swiftTypeToKotlin(getter.functionSignature.result.type) else { continue }

      guard let (getParams, getArgs) = subscriptParamsAndArgs(getter, isSetter: false) else {
        lines.append("  // Skipped subscript getter: unsupported parameter type")
        continue
      }
      let getThunk = cinteropName(nativeThunkName(decl: getter))
      let getCall = "\(getThunk)(\((getArgs + ["__ptr()"]).joined(separator: ", ")))"
      lines.append("  operator fun get(\(getParams.joined(separator: ", "))): \(ret) {")
      lines += renderFunctionBody(callExpr: getCall, ret: ret, baseIndent: "    ")
      lines.append("  }")

      if let setter = pair.setter {
        guard let (setParams, setArgs) = subscriptParamsAndArgs(setter, isSetter: true) else {
          lines.append("  // Skipped subscript setter: unsupported parameter type")
          continue
        }
        let setThunk = cinteropName(nativeThunkName(decl: setter))
        lines.append("  operator fun set(\(setParams.joined(separator: ", "))) {")
        lines.append("    \(setThunk)(\((setArgs + ["__ptr()"]).joined(separator: ", ")))")
        lines.append("  }")
      }
    }
    return lines
  }

  /// The Kotlin parameter declarations and thunk call-site arguments for a
  /// subscript accessor's parameters. For a setter the trailing `newValue`
  /// parameter is named `newValue`; index parameters keep their Swift names.
  func subscriptParamsAndArgs(
    _ decl: ImportedFunc, isSetter: Bool
  ) -> (params: [String], args: [String])? {
    var params: [String] = []
    var args: [String] = []
    let all = decl.functionSignature.parameters
    for (i, p) in all.enumerated() {
      let name = (isSetter && i == all.count - 1) ? "newValue" : parameterName(p, at: i)
      guard let pa = kotlinParamAndArg(p, name: name) else { return nil }
      params.append(pa.param)
      args.append(contentsOf: pa.callArgs)
    }
    return (params, args)
  }

}
