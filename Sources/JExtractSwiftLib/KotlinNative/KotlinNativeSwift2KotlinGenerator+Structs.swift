//
//  KotlinNativeSwift2KotlinGenerator+Structs.swift
//  swift-java
//
//  Value-semantics model for Swift structs in kotlinNative mode.
//
//  Each Swift `struct` becomes a single `SwiftCopyable` Kotlin class over an
//  `NSObject` box — the read-only surface: property getters, non-mutating methods,
//  static methods, and `copy()`. Mutating operations are top-level extensions on
//  `Inout<Struct>`:
//    - settable primitive / String field → `var Inout<Struct>.p`
//    - settable custom-type field        → a *connected* `val Inout<Struct>.p:
//      Inout<Field>` (nested `s.p.x = …` writes back to `s`) plus a scoped
//      `fun Inout<Struct>.mutateP { … }` (reads once, batches edits, writes back once)
//    - `mutating` method                 → `fun Inout<Struct>.m(…)`
//    - settable subscript                → `operator fun Inout<Struct>.set(…)`
//      (the read-only `operator fun get(…)` stays on the value class)
//
//  Each setter / `mutating` thunk raises `self`, mutates a local, and returns a
//  freshly re-boxed value; the extension stores it back into the holder
//  (`unsafeValue = Struct(…)`), so the mutation persists with value semantics. A
//  per-struct `copy` thunk boxes a fresh independent value.
//
//  KNOWN LIMITATIONS: `consuming` is not expressible; struct members that take
//  `inout` parameters are skipped; a captured connected sub-holder can go stale
//  (use `mutateP { … }` to avoid).
//
import CodePrinting
import SwiftSyntax

extension KotlinNativeSwift2KotlinGenerator {

  // MARK: - Kotlin wrapper emission

  /// Emit a Swift struct as a single `SwiftCopyable` value class (read-only surface
  /// + `copy()`), followed by the `Inout<Struct>` extensions for its mutating
  /// operations (settable properties and `mutating` methods).
  func printKotlinStruct(_ printer: inout CodePrinter, _ nominal: ImportedNominalType) {
    let name = nominal.swiftNominal.flatName
    let copyThunk = cinteropName(copyThunkName(name))

    // Initializers with `inout` params, and subscripts with an `inout` index, are
    // skipped (matching a borrowing member that takes an `inout` parameter).
    let inits = nominal.initializers.filter { memberIsEmittable($0) && !hasInoutParam($0) }
    let allMethods = nominal.methods.filter { memberIsEmittable($0) && !$0.isStatic }
    // Read-only surface: borrowing (non-mutating) methods without `inout` params.
    let readOnlyMethods = allMethods.filter { !inoutSelfIsMutableStruct($0) && !hasInoutParam($0) }
    // Mutating methods (mutable `inout` struct `self`); may also carry `inout` params.
    let mutatingMethods = allMethods.filter { inoutSelfIsMutableStruct($0) }
    let statics = nominal.methods.filter { memberIsEmittable($0) && $0.isStatic && !hasInoutParam($0) }
    let emittableVars = nominal.variables.filter(memberIsEmittable)
    let props = structProperties(emittableVars)
    let subscripts = subscriptPairs(emittableVars).filter {
      !hasInoutParam($0.getter) && !($0.setter.map(hasInoutParam) ?? false)
    }

    // ---- Read-only value class: getters, non-mutating methods, `copy()`. ----
    printer.print("@OptIn(ExperimentalNativeApi::class)")
    printer.print("class \(name) internal constructor(val obj: NSObject) : SwiftCopyable {")
    printer.print("  internal fun __ptr(): COpaquePointer = interpretCPointer<CPointed>(obj.objcPtr())!!")
    for i in inits { printer.print(renderStructConstructor(i)) }
    for p in props { for l in renderStructReadOnlyProperty(p) { printer.print(l) } }
    for m in readOnlyMethods {
      for l in renderStructMethod(m, isStatic: false) { printer.print(l) }
    }
    // Subscript getters are read-only members on the value class (borrowing `self`).
    for pair in subscripts { for l in renderStructSubscriptGetter(pair.getter) { printer.print(l) } }
    if !statics.isEmpty {
      printer.print("  companion object {")
      for m in statics { for l in renderStructMethod(m, isStatic: true) { printer.print("  \(l)") } }
      printer.print("  }")
    }
    printer.print("  override fun copy(): \(name) = \(name)(wrapSwiftObject { \(copyThunk)(__ptr()) })")
    printer.print("}")

    // ---- Mutating operations as `Inout<Struct>` extensions. Each seeds a `self`
    // box cell, calls the mutating thunk (which re-boxes `self` back into the cell),
    // and swaps the holder to the re-boxed value. ----
    for p in props where p.setter != nil {
      for l in renderInoutSetterExtension(p, structName: name) { printer.print(l) }
    }
    for m in mutatingMethods {
      for l in renderInoutMutatingExtension(m, structName: name) { printer.print(l) }
    }
    for pair in subscripts where pair.setter != nil {
      for l in renderInoutSubscriptSetterExtension(pair.setter!, structName: name) { printer.print(l) }
    }
  }

  /// A read-only subscript getter (`operator fun get`) on the struct value class.
  private func renderStructSubscriptGetter(_ getter: ImportedFunc) -> [String] {
    guard let ret = swiftTypeToKotlin(getter.functionSignature.result.type) else {
      return ["  // Skipped subscript getter: unsupported return type"]
    }
    guard let (params, args) = subscriptParamsAndArgs(getter, isSetter: false) else {
      return ["  // Skipped subscript getter: unsupported parameter type"]
    }
    let call = "\(cinteropName(nativeThunkName(decl: getter)))(\((args + ["__ptr()"]).joined(separator: ", ")))"
    var lines = ["  operator fun get(\(params.joined(separator: ", "))): \(ret) {"]
    lines += renderFunctionBody(callExpr: call, ret: ret, baseIndent: "    ")
    lines.append("  }")
    return lines
  }

  /// A settable subscript's `set` as `operator fun Inout<Struct>.set(...)`: mutate
  /// `self` through the box cell (`structMutationBlock`), mirroring a `mutating`
  /// method.
  private func renderInoutSubscriptSetterExtension(_ setter: ImportedFunc, structName: String) -> [String] {
    guard let (params, args) = subscriptParamsAndArgs(setter, isSetter: true) else {
      return ["// Skipped subscript setter: unsupported parameter type"]
    }
    let thunk = cinteropName(nativeThunkName(decl: setter))
    var lines = [
      "@OptIn(ExperimentalNativeApi::class)",
      "operator fun Inout<\(structName)>.set(\(params.joined(separator: ", "))) {",
    ]
    lines += structMutationBlock(structName: structName, thunk: thunk, leadingArgs: args,
                                 marshals: [], ret: .unit, indent: "  ")
    lines.append("}")
    return lines
  }

  // MARK: - Member rendering (Kotlin)

  /// A struct constructor delegating to the init thunk.
  private func renderStructConstructor(_ decl: ImportedFunc) -> String {
    guard let (params, args) = structParamsAndArgs(decl) else {
      return "  // Skipped \(decl.displayName): unsupported parameter type"
    }
    let thunk = cinteropName(nativeThunkName(decl: decl))
    return "  constructor(\(params.joined(separator: ", "))) : this(wrapSwiftObject { \(thunk)(\(args.joined(separator: ", "))) })"
  }

  /// A non-mutating instance method or a static method on the value class.
  private func renderStructMethod(_ decl: ImportedFunc, isStatic: Bool) -> [String] {
    guard let ret = swiftTypeToKotlin(decl.functionSignature.result.type) else {
      return ["  // Skipped \(decl.displayName): unsupported return type"]
    }
    guard let (params, args) = structParamsAndArgs(decl) else {
      return ["  // Skipped \(decl.displayName): unsupported parameter type"]
    }
    // Instance methods pass `self` (the box pointer) last.
    let callArgs = isStatic ? args : args + ["__ptr()"]
    let callExpr = "\(cinteropName(nativeThunkName(decl: decl)))(\(callArgs.joined(separator: ", ")))"
    var lines = ["  fun \(decl.name)(\(params.joined(separator: ", "))): \(ret) {"]
    lines += renderFunctionBody(callExpr: callExpr, ret: ret, baseIndent: "    ")
    lines.append("  }")
    return lines
  }

  /// A read-only `val` property (getter only) on the value class.
  private func renderStructReadOnlyProperty(_ p: StructProperty) -> [String] {
    let getterThunk = cinteropName(nativeThunkName(decl: p.getter))
    var lines = ["  val \(p.name): \(p.type)", "    get() {"]
    lines += returnBodyLines(callExpr: "\(getterThunk)(__ptr())", ret: p.type, indent: "      ", finalPrefix: "return ")
    lines.append("    }")
    return lines
  }

  /// Mutation extensions for one settable struct property, on `Inout<Struct>`.
  ///
  /// - A **primitive / String** field is a `var Inout<Struct>.name`: read from the
  ///   held value, write by calling the setter thunk (which returns the re-boxed
  ///   value) and storing it back.
  /// - A **custom-type** field gets both a *connected* `Inout<Field>` getter
  ///   (`rect.topLeft.x = …` writes back through the parent) and a scoped
  ///   `mutate<Name> { … }` helper (batched, no stale-alias hazard).
  private func renderInoutSetterExtension(_ p: StructProperty, structName: String) -> [String] {
    guard let setter = p.setter else { return [] }
    let setterThunk = cinteropName(nativeThunkName(decl: setter))

    // The mutation block that writes `fieldPtr` into the field via the setter thunk
    // and swaps the holder to the re-boxed parent, at the given indent.
    func writeBackParent(_ fieldArg: String, indent: String) -> [String] {
      structMutationBlock(structName: structName, thunk: setterThunk, leadingArgs: [fieldArg],
                          marshals: [], ret: .unit, indent: indent)
    }

    guard case .object(let fieldType) = p.type else {
      let valueArg = p.type == .string ? "value.cstr" : "value"
      var lines = [
        "@OptIn(ExperimentalNativeApi::class)",
        "var Inout<\(structName)>.\(p.name): \(p.type)",
        "  get() = unsafeValue.\(p.name)",
        "  set(value) {",
      ]
      lines += writeBackParent(valueArg, indent: "    ")
      lines.append("  }")
      return lines
    }

    let cap = p.name.prefix(1).uppercased() + p.name.dropFirst()
    var lines = [
      // Connected sub-holder: mutations propagate back to the parent.
      "@OptIn(ExperimentalNativeApi::class)",
      "val Inout<\(structName)>.\(p.name): Inout<\(fieldType)>",
      "  get() = Inout(unsafeValue.\(p.name)) { newValue ->",
    ]
    lines += writeBackParent("newValue.__ptr()", indent: "    ")
    lines.append("  }")
    // Scoped batched mutation: read once, mutate in the block, write back once.
    lines.append("@OptIn(ExperimentalNativeApi::class)")
    lines.append("fun Inout<\(structName)>.mutate\(cap)(block: Inout<\(fieldType)>.() -> Unit) {")
    lines.append("  val field = Inout(unsafeValue.\(p.name))")
    lines.append("  field.block()")
    lines += writeBackParent("field.unsafeValue.__ptr()", indent: "  ")
    lines.append("}")
    return lines
  }

  /// `fun Inout<Struct>.name(...)`: mutate `self` through the box cell. The `self`
  /// slot carries the re-boxed value (written back by the thunk), so — unlike the
  /// old return-slot swap — the return slot is free for the method's own result.
  /// Non-`Void` (scalar) returns and `inout` parameters are both supported.
  private func renderInoutMutatingExtension(_ decl: ImportedFunc, structName: String) -> [String] {
    let ret = swiftTypeToKotlin(decl.functionSignature.result.type)!  // vetted by memberIsEmittable
    guard let (params, args, marshals) = structMemberParamsArgsMarshals(decl) else {
      return ["// Skipped \(decl.displayName): unsupported parameter type"]
    }
    let thunk = cinteropName(nativeThunkName(decl: decl))
    let retSuffix = (ret == .unit) ? "" : ": \(ret)"
    var lines = [
      "@OptIn(ExperimentalNativeApi::class)",
      "fun Inout<\(structName)>.\(decl.name)(\(params.joined(separator: ", ")))\(retSuffix) {",
    ]
    lines += structMutationBlock(structName: structName, thunk: thunk, leadingArgs: args,
                                 marshals: marshals, ret: ret, indent: "  ",
                                 prefix: ret == .unit ? "" : "return ")
    lines.append("}")
    return lines
  }

  // MARK: - Member rendering helpers

  private func hasInoutParam(_ decl: ImportedFunc) -> Bool {
    decl.functionSignature.parameters.contains { $0.convention == .inout }
  }

  /// Kotlin parameter declaration + thunk call argument for a single struct member
  /// parameter. Custom types pass their box pointer via `__ptr()` (`ptr` alone
  /// collides with the `kotlinx.cinterop` extension property of that name).
  private func structParamAndArg(_ p: SwiftParameter, name: String) -> (param: String, arg: String)? {
    guard let kt = swiftTypeToKotlin(p.type) else { return nil }
    switch kt {
    case .string:  return ("\(name): \(kt)", "\(name).cstr")
    case .object:  return ("\(name): \(kt)", "\(name).__ptr()")
    default:       return ("\(name): \(kt)", name)
    }
  }

  /// The Kotlin parameter declarations and thunk call arguments for all of `decl`'s
  /// parameters, or `nil` if any type is unsupported. (Emittable members never hit
  /// the `nil` path — `memberIsEmittable` has already vetted the types.)
  private func structParamsAndArgs(_ decl: ImportedFunc) -> (params: [String], args: [String])? {
    var params: [String] = []
    var args: [String] = []
    for (i, p) in decl.functionSignature.parameters.enumerated() {
      guard let pa = structParamAndArg(p, name: parameterName(p, at: i)) else { return nil }
      params.append(pa.param)
      args.append(pa.arg)
    }
    return (params, args)
  }

  /// Like `structParamsAndArgs`, but also handles `inout` parameters: each `inout T`
  /// becomes a Kotlin `Inout<T>` parameter whose native cell (`<name>_cell`) is
  /// allocated by `structMutationBlock` and passed as `<name>_cell.ptr`. Returns the
  /// Kotlin parameter decls, the thunk leading args (before `self`), and the `inout`
  /// marshals to materialize inside the `memScoped` block.
  private func structMemberParamsArgsMarshals(
    _ decl: ImportedFunc
  ) -> (params: [String], args: [String], marshals: [InoutMarshal])? {
    var params: [String] = []
    var args: [String] = []
    var marshals: [InoutMarshal] = []
    for (i, p) in decl.functionSignature.parameters.enumerated() {
      let name = parameterName(p, at: i)
      if p.convention == .inout {
        guard let flavor = inoutFlavor(p.type), let kt = swiftTypeToKotlin(p.type) else { return nil }
        let cellVar = "\(name)_cell"
        params.append("\(name): Inout<\(kt)>")
        args.append("\(cellVar).ptr")
        marshals.append(InoutMarshal(paramName: name, cellVar: cellVar, flavor: flavor))
      } else {
        guard let pa = structParamAndArg(p, name: name) else { return nil }
        params.append(pa.param)
        args.append(pa.arg)
      }
    }
    return (params, args, marshals)
  }

  /// The lines of a `memScoped { … }` block that mutates a struct through its `self`
  /// box cell, shared by every `Inout<Struct>` mutation extension (property setters,
  /// `mutating` methods, subscript setters, connected-field write-backs):
  ///
  /// 1. materialize any `inout` parameter cells (`marshals`);
  /// 2. seed a `self` cell (`COpaquePointerVar`) from `unsafeValue.__ptr()`;
  /// 3. call `thunk` with `leadingArgs` followed by `self_slot.ptr` (the thunk
  ///    re-boxes the mutated `self` back into the cell);
  /// 4. copy any `inout` params back into their holders;
  /// 5. swap the holder to the re-boxed value (`unsafeValue = Struct(…)`).
  ///
  /// For a non-`Unit` `ret` the thunk's result is the block's trailing value; the
  /// caller passes `prefix: "return "` so the enclosing function returns it.
  private func structMutationBlock(
    structName: String, thunk: String, leadingArgs: [String],
    marshals: [InoutMarshal], ret: KotlinType, indent: String, prefix: String = ""
  ) -> [String] {
    let inner = indent + "  "
    let isVoid = (ret == .unit)
    var lines = ["\(indent)\(prefix)memScoped {"]
    for m in marshals { lines += inoutCellPrologue(m, source: inoutRefSource(m), indent: inner) }
    lines.append("\(inner)val self_slot = alloc<COpaquePointerVar>()")
    lines.append("\(inner)self_slot.value = unsafeValue.__ptr()")
    let callArgs = (leadingArgs + ["self_slot.ptr"]).joined(separator: ", ")
    let callExpr = "\(thunk)(\(callArgs))"
    if isVoid {
      lines.append("\(inner)\(callExpr)")
    } else {
      lines.append(inoutResultCapture(ret: ret, callExpr: callExpr, indent: inner))
    }
    for m in marshals { lines.append("\(inner)\(m.paramName).unsafeValue = \(inoutCellReadBack(m))") }
    lines.append("\(inner)unsafeValue = \(structName)(wrapSwiftObject { self_slot.value })")
    if !isVoid { lines.append("\(inner)_result") }
    lines.append("\(indent)}")
    return lines
  }

  /// A struct property paired with its getter and optional setter.
  struct StructProperty {
    let name: String
    let type: KotlinType
    let getter: ImportedFunc
    let setter: ImportedFunc?
  }

  /// Pair up getter/setter accessors by property name, preserving declaration order.
  private func structProperties(_ variables: [ImportedFunc]) -> [StructProperty] {
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
    return order.compactMap { n in
      guard let g = getters[n], let t = swiftTypeToKotlin(g.functionSignature.result.type) else { return nil }
      return StructProperty(name: n, type: t, getter: g, setter: setters[n])
    }
  }

  // MARK: - Swift `@_cdecl` thunks

  /// The C symbol of the per-struct `copy` thunk (raise + re-box a fresh copy).
  func copyThunkName(_ flatName: String) -> String {
    "swiftjava_\(swiftModuleName)_\(flatName)_copy"
  }

  /// The `@_cdecl` `copy` thunk: raise the struct value (a copy, by value semantics)
  /// and box a fresh independent `AnyObject` for it.
  func copyThunk(for nominal: ImportedNominalType) -> DeclSyntax {
    let cName = copyThunkName(nominal.swiftNominal.flatName)
    let raise = objectRaiseExpr(from: "self", swiftType: nominal.swiftNominal.qualifiedName)
    return DeclSyntax(stringLiteral: """
      @_cdecl("\(cName)")
      public func \(cName)(_ self: UnsafeRawPointer) -> UnsafeMutableRawPointer {
          let _result = (\(raise)) as AnyObject
          return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
      }
      """)
  }

  // MARK: - C declarations

  /// A `void *f(<params…>)` cdecl signature (all struct thunks that return a box).
  private func boxReturningCdecl(_ params: [SwiftParameter]) -> SwiftFunctionSignature {
    let knownTypes = SwiftKnownTypes(symbolTable: symbolTable)
    return SwiftFunctionSignature(
      selfParameter: nil,
      parameters: params,
      result: SwiftResult(convention: .direct, type: knownTypes.unsafeMutableRawPointer),
      effectSpecifiers: [],
      genericParameters: [],
      genericRequirements: []
    )
  }

  /// The C declaration for a struct's `copy` thunk: `void *f(const void *)`.
  func copyCFunction(for nominal: ImportedNominalType) throws -> CFunction {
    let knownTypes = SwiftKnownTypes(symbolTable: symbolTable)
    let selfParam = SwiftParameter(convention: .byValue, parameterName: "self", type: knownTypes.unsafeRawPointer)
    return try CFunction(cdeclSignature: boxReturningCdecl([selfParam]),
                         cName: copyThunkName(nominal.swiftNominal.flatName))
  }
}
