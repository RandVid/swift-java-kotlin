# Kotlin/Native Class/Struct Support — Implementation & Review Notes

Status of the custom `class`/`struct` support added to the `kotlinNative` jextract
mode, plus a high-effort code review of the change. Implements the design in
`.claude/ClassImpl.md` (Option B — Swift-malloc delegation: the Swift `@_cdecl`
thunk allocates the box and returns an opaque pointer; the Kotlin host stays
layout-blind).

---

## 1. What was implemented

Each imported Swift nominal type (class **or** struct, uniform box path) becomes a
Kotlin/Native wrapper class holding an opaque `COpaquePointer` to a Swift-allocated
box. Three artifacts are emitted from one model and must agree on the C ABI:

1. **Kotlin wrapper** (`<Module>.kt`) — the wrapper class; imports `SwiftHandle` from `SwiftKitKN`.
2. **Plain-C header** (`<Module>.h`) — declarations the cinterop `.def` consumes.
3. **Swift `@_cdecl` thunks** (`<Module>Module+SwiftJava.swift`).

### Capabilities
- Constructors, instance methods, static methods, stored-property get/set.
- Custom types as parameters and return values (top-level functions and members).
- Lifetime: a generated `SwiftHandle` runs a per-type `_destroy` thunk
  (`deinitialize(count:1)` + `deallocate()`) exactly once — via
  `AutoCloseable.close()` / `use {}` (deterministic) or a GC `createCleaner`
  (`@OptIn(ExperimentalNativeApi::class)`), guarded by a CAS `AtomicInt`. Calls
  after destroy throw via `ensureAlive()`.

### Member type scope
Member parameter/return types support: all primitives, `Bool`, `Float`, `Double`,
`String`, **optional primitives/strings** (`Int?`, `String?`, …), `[UInt8]`/`UByteArray`,
and custom imported class/struct types — across constructors, instance/static
methods, and property accessors. Enums, protocols, generics, subscripts, async,
and throwing members are skipped with a comment.

### Files changed
| File | Role |
|------|------|
| `Sources/JExtractSwiftLib/KotlinNative/KotlinType.swift` | `+ case object(String)` |
| `…/KotlinNativeSwift2KotlinGenerator.swift` | type mapping, `.object` param/return in `resolve()`, header emission, `cinteropName` `$`-escaping, `importedTypeQualifiedNames`, `destroyThunkName`; imports `SwiftHandle` from `SwiftKitKN`; `NativeGlobalVar` + `resolvedGlobalVariables()` + `printKotlinGlobalVar()` for top-level vars; global var C header declarations |
| `…/KotlinNativeSwift2KotlinGenerator+Classes.swift` (new) | `memberIsEmittable` (allows `[UInt8]` + optionals for all member kinds; mirrors `loweredCdeclForThunk` stripping for the CdeclLowering gate); `renderMethod` (usePinned + memScoped for arrays); `printKotlinClass`, `renderConstructor`/`renderProperties`, `kotlinParamAndArg` |
| `SwiftKitKN/` (new module) | Kotlin/Native runtime library; `SwiftHandle` (`org.swift.swiftkit.kn`) — public, reusable across all generated modules; macOS-only Gradle module |
| `…/KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` | member gate, `makeThunkDecl`, `nominalAllocatingThunk`, `destroyThunk`; `arrayReturningThunk` extended to append `self` for instance methods; `optionalReturningThunk` + `stringOptionalAwareThunk` extended with self dispatch + getter-access fix (no parens); `memberCFunction` extended with array-return and optional-return custom CFunction branches; default/object-return paths switched to `loweredCdeclForThunk` to strip `String?` params; global var thunk emission |
| `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeClassTests.swift` (new) | 38 generation tests (incl. 7 for array params/returns on methods) |
| `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift` | +4 global variable tests (`globalVar_readWrite_kotlin`, `globalVar_readOnly_kotlin`, `globalVar_string_kotlin`, `globalVar_readWrite_swiftThunk`) |
| `Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib/SimpleSwiftLib.swift` | `Counter` class (+ array methods: `accumulate`, `encoded`, `transform`, `zeroBytes`), `Point`/`Holder` structs, `combine`, init/deinit counters, `globalScore`/`appVersion` globals |
| `Samples/KotlinNativeSampleApp/src/macosArm64Test/kotlin/SimpleSwiftLibTest.kt` | functional + memory + GC cleaner + global var + array-on-method runtime tests |
| `Samples/KotlinNativeSampleApp/build.gradle.kts` | `inputs.file(swiftJavaTool)` + `SwiftKitKN` dependency |
| `CLAUDE.md` | doc refresh |

### Verification performed
- `swift test` → **130 KotlinNative** unit tests pass (75 top-level + 49 class,
  incl. array-on-member, optional-on-member, full-type global variable tests; total suite ~600+).
- `Samples/KotlinNativeSampleApp/ci-validate.sh` → **BUILD SUCCESSFUL** (original
  run); array, optional, and global-var integration tests added but require a fresh
  `ci-validate.sh` run to regenerate bindings.

### Bugs found & fixed during implementation
- **Member symbols missing from the C header** — `writeCinteropHeader` only
  emitted top-level functions; added member + destroy C declarations.
- **`$` in accessor symbols** (`value$get`) broke Kotlin parsing (read as string
  templates) — added `cinteropName` to backtick-escape such references (also
  covers dedup suffixes `$1`).
- **Property getter returning a custom type** emitted `…pointee.counter()` —
  calling a property like a function; fixed `nominalAllocatingThunk` to emit
  member access without parens for getters (locked by 2 unit tests).
- **Stale Gradle generation** — `generateKotlinNativeBindings` was cached
  "up-to-date" after a tool rebuild and reused stale wrappers; fixed by declaring
  the tool binary as a task input.

---

## 2. Memory-safety tests added

`Counter` got a `deinit` plus module-global `counterInitCount()` /
`counterDeinitCount()` accessors so Kotlin can observe alloc/free. Tests assert
**deltas** (independent of other tests):

| Test | Proves |
|------|--------|
| `testMemory_destroyRunsExactlyOnceOnClose` | `close()` → exactly one Swift `deinit` (no leak, no double-destroy) |
| `testMemory_doubleCloseIsIdempotent` | second `close()` is a CAS no-op (no double-free) |
| `testMemory_noLeakAcrossManyObjects` | 100 construct/close cycles → exactly 100 deinits |
| `testMemory_returnedObjectOutlivesProducerAndSharedIdentity` | `selfReference()` returns the same object (+1 retain); closing one wrapper does **not** free early, freed exactly once; shared identity |
| `testMemory_structReleasesReferenceMember` | `Holder` struct `_destroy` releases its `Counter` field exactly once |

GC-cleaner path is now also **directly asserted** via three tests. The key design
constraint: object creation must be in a separate non-inline function so the
Counter's stack frame is completely gone before `GC.collect()` runs. If the
allocation is inline (e.g. `run { Counter(1L) }`), the Counter reference lives
in the test method's frame and the GC treats it as a live root — it won't be
collected. With a separate frame, Kotlin/Native's non-generational GC collects
both `Counter` and `__cleaner` in the same sweep and fires the cleaner callback,
so a single `GC.collect()` call is sufficient.

| Test | Proves |
|------|--------|
| `testMemory_cleanerDestroysSwiftObject` | cleaner fires and calls `_destroy` once when wrapper is never explicitly closed |
| `testMemory_cleanerIsNoOpWhenAlreadyClosed` | CAS guard prevents double-destroy when `close()` ran before GC |
| `testMemory_cleanerHandlesBulkObjects` | 50 unclosed wrappers all cleaned in a single `collect()` sweep — no leaks |

---

## 3. Code review (high effort) — findings

All findings were in **untested edge paths**; the unit tests + sample were
internally consistent. Common root cause for #1–#3: top-level functions are gated
by `resolve()` (which lowers inside a `do/catch`), but members used a separate,
weaker `memberIsEmittable` that did not attempt lowering or mirror the throwing
rules.

**Status: #1–#4 and #6–#7 are FIXED (see §4 and §5). #5 remains documented as a follow-up (see §5).**

### Confirmed bugs (ranked)

**1. Top-level throwing function returning a custom type → undefined symbol (link failure).** *(FIXED)*
`resolve()` had no `isThrowing` skip for the `.object` return case, but
`writeSwiftThunkSources` did. So `public func make() throws -> Counter` was
emitted in the Kotlin wrapper **and** the C header, but its `@_cdecl` thunk was
skipped → cinterop binds a symbol that is never defined.

**2. Throwing functions/members omit the `result$throws` error-out arg in the Kotlin call.** *(FIXED)*
`cdeclThunk`/`cdeclSignature` append a trailing `result$throws` pointer for any
throwing function, so the thunk **and** header have an extra parameter — but
`printKotlinFunction` (top-level) and `renderMethod` (members) build the call from
regular params + `self` only. `class Box { func risky() throws -> Int }` → Kotlin
emits `swiftjava_…_risky(self)` with one fewer arg than the bound C function →
Kotlin/Native compile error.

**3. Member whose type maps but cannot be C-lowered → unresolved reference.** *(FIXED)*
`memberIsEmittable` checked only `swiftTypeToKotlin(...) != nil` + not-optional/array;
it never attempted the lowering. The Kotlin class printer then emitted the call
unconditionally, while `makeThunkDecl`/`memberCFunction` swallow lowering errors
via `try?`. Concrete trigger: an `inout` parameter — `class Box { func f(x: inout Int) }`.

**4. `importedTypeNames` matched on the *simple* type name only.** *(FIXED)*
`swiftTypeToKotlin` mapped any nominal whose `nominalTypeDecl.name` was in
`importedTypeNames` to `.object(name)`, wired to `destroyThunkName(name)`. A
parameter/return whose simple name collided with an imported type (nested
`Outer.Box` vs top-level `Box`, or a same-named type from another module) was
mis-mapped to the wrong wrapper/destroy symbol → wrong-type `.pointee` cast, and
two same-simple-name types produced duplicate Kotlin classes + colliding
`_destroy` symbols.

**5. Setter-only property emits an orphan symbol.** *(OPEN — see §6)*
The thunk loop + header iterate `variables` per accessor, so a setter whose
property has no emittable getter gets its `$set` thunk/header decl emitted, but
`renderProperties` builds its list from getters only → no Kotlin accessor.
Harmless (an exported, never-called symbol — no link error), and essentially
unreachable in valid Swift (no set-only properties), but the Kotlin and
thunk/header member sets can structurally desync.

### Cleanup / lower severity

**6. Return-body logic duplicated** between `printKotlinFunction` (top-level) and
`appendReturnBody` (members) — the `.string`/`.optional`/`.object`/`.unit` cases
are encoded twice and will drift. Same class of duplication: the stripped-signature
build in `resolve()` vs `makeThunkDecl`, and the object-return `CFunction` built in
three places. *(FIXED — see §5.)*

**7. Dead guard:** `renderConstructor`'s failable-init check
(`swiftTypeToKotlin(...).map(isOptional) == true`) can never fire —
`swiftTypeToKotlin` returns `nil` (not `.optional`) for `Optional<CustomType>`,
and `memberIsEmittable` rejects it earlier. *(FIXED — see §5.)*

### Verified NOT bugs (refuted)
- `self` ordering (regular params then `self`), struct mutable-setter `self`,
  `cinteropName` `$`-escaping coverage, and `functionThunkName` dedup stability
  are all consistent across the three artifacts.
- The unit test asserting a Swift `func …child$get(...)` with a literal `$` is
  valid — the sample compiled exactly such thunks (`ci-validate` BUILD
  SUCCESSFUL), so it is not asserting non-compilable output.
- The memory tests are not racy as written: every wrapper is explicitly closed,
  so Swift `deinit` only runs on the test thread (a cleaner on an already-closed
  handle is a CAS no-op and never increments the counter). It is a fragility (a
  future *unclosed* `Counter` would make deltas GC-timing-dependent), not a
  current data race.
- Swift-`allocate` freed by C `free` on string/optional returns is **pre-existing**
  (untouched paths) and works on the target runtime; object returns correctly use
  the matching `deallocate` via the destroy thunk.

---

## 4. Fixes applied (#1–#4)

Approach: **skip what we can't faithfully translate, on every artifact, via one
gate per surface.** Throwing functions are dropped everywhere; the member gate now
attempts the C lowering so anything unlowerable is dropped consistently; and type
identity is qualified/flat throughout.

**#1 + #2 — throwing functions are not translated anywhere.**
- `resolve()` (top-level): added `guard decl.isThrowing == false` →
  `// Skipped <name>: throwing functions are not supported in kotlinNative mode`.
  This drives the Kotlin wrapper *and* the C header (both consume
  `resolvedFunctions()`).
- `writeSwiftThunkSources` top-level loop: added `decl.isThrowing == false` to the
  gate so the thunk file matches.
- `memberIsEmittable`: now returns `false` for **any** throwing member (was only
  throwing-`+`-object). This single gate is consulted by the Kotlin class printer,
  the member thunk loop, and the header member loop.
- Net effect: a throwing function/member is dropped on all three artifacts, so the
  missing-`result$throws`-arg mismatch can no longer occur.

**#3 — un-lowerable signatures are dropped consistently.**
`memberIsEmittable` now ends with a real lowering attempt:
```swift
do { _ = try CdeclLowering(symbolTable: symbolTable)
        .lowerFunctionSignature(decl.functionSignature) }
catch { return false }
```
A signature that maps type-by-type via `swiftTypeToKotlin` but cannot be C-lowered
(e.g. an `inout` parameter) now fails the gate, so the Kotlin wrapper, the C
header, and the Swift thunk all skip it together — no more "Kotlin emits a call to
a symbol the header/thunk never produced." (Top-level was already protected by
`resolve()`'s `do/catch`.)

**#4 — qualified / flat identity instead of the bare simple name.**
- Matching: `importedTypeNames` (simple) → `importedTypeQualifiedNames`
  (`swiftNominal.qualifiedName`); `swiftTypeToKotlin` matches on
  `nominalTypeDecl.qualifiedName` and returns `.object(nominalTypeDecl.flatName)`.
- Kotlin wrapper class name → `swiftNominal.flatName` (e.g. `Outer_Box`).
- `_destroy` C symbol (`destroyThunk` + `destroyCFunction`) → `flatName`, matching
  the member-thunk naming (`ThunkNameRegistry` already uses `flatName`).
- Swift type references in the hand-rolled thunks use the **qualified** Swift name:
  `nominalAllocatingThunk` box type → `qualifiedName`; `destroyThunk` →
  `assumingMemoryBound(to: <qualifiedName>.self)`.
- For top-level types `name == qualifiedName == flatName`, so existing output is
  unchanged; nested / same-simple-name types now get unique, non-colliding
  wrappers and symbols.

**Regression tests** (in `KotlinNativeClassTests.swift`, suite now 105 KN tests):
`throwingTopLevelFunction_isSkipped` / `_noSwiftThunk`, `throwingMethod_isSkipped`
/ `_noSwiftThunk`, `inoutParameterMethod_isSkipped` / `_noSwiftThunk`,
`nestedType_usesFlatNameForClassAndDestroy_kotlin`,
`nestedType_destroyThunkUsesQualifiedSwiftType`.

> Note: the sample's `Counter.describe()` is non-throwing, so no sample/test
> referenced a throwing member; the throwing skip did not require sample changes.
> The full `ci-validate.sh` end-to-end run was not re-run after these generator
> changes (unit tests cover the changed code paths).

---

## 5. Issue #5 — setter-only property orphan symbol (OPEN)

### Symptom
A property setter can get a Swift `@_cdecl` `$set` thunk **and** a C-header
declaration emitted, while the Kotlin wrapper emits **no** corresponding
accessor — leaving an exported, cinterop-bound symbol that nothing in Kotlin ever
calls (dead, not a link error).

### Why it happens (structural asymmetry)
The two sides enumerate properties differently:
- **Kotlin** (`renderProperties`, `+Classes.swift`) is **getter-driven**: it builds
  `order` from getters, then attaches a `set` block only when a matching setter
  exists. A property with no (emittable) getter produces no Kotlin member at all.
- **Swift thunks** (`writeSwiftThunkSources` member loop) and the **C header**
  (`writeCinteropHeader` member loop) iterate `nominal.variables.filter(memberIsEmittable)`
  **per accessor** — each emittable getter and each emittable setter independently
  gets a thunk + a header declaration.

So if a setter is emittable while its property's getter is not, the setter symbol
is emitted by two of the three artifacts but referenced by none.

### Direction matters
- **Harmless direction (the one that can occur):** setter emitted, no Kotlin
  caller → orphan exported symbol. No link error, just dead code.
- **Dangerous inverse (cannot occur):** Kotlin emits an accessor whose thunk was
  skipped → link error. This is impossible because the Kotlin `get`/`set` emission
  and the corresponding thunk are both gated by the *same* `memberIsEmittable`.

### Reachability: essentially nil in valid Swift
Swift has **no set-only properties** — a computed property with a `set` must also
declare a `get`, and getter & setter share the same type (so they are emittable
together or not at all). The only ways to get a setter without an emittable getter
are constructs Swift does not allow (write-only) or a contrived throwing-getter +
settable property, which is also not valid. Hence this is a *latent structural*
inconsistency, not a reproducible bug today — which is why it was left for last.

### Recommended fix (when addressed)
Drive both sides from one paired view of properties so they cannot drift:
- Build `[(name, getter, setter?)]` pairs once (keyed by property name, requiring a
  getter), and have the Kotlin printer, the thunk loop, and the header loop all
  consume that same structure (instead of the thunk/header loops iterating raw
  `variables`); **or**
- Minimally, in the member thunk/header loops, skip a setter whose property has no
  emittable getter (mirror `renderProperties`' getter-driven rule), so the emitted
  symbol set always matches the Kotlin wrapper.

Land it with a regression test once a way to construct the asymmetry is available
(e.g. if KN later admits an accessor shape where getter/setter emittability can
legitimately differ).

### Related lower-severity cleanups *(FIXED)*
- **#6 — duplication removed via shared helpers** (all behavior-preserving;
  verified by the exact-text generation tests):
  - `returnBodyLines(callExpr:ret:indent:finalPrefix:)` (main file) now produces the
    per-return-kind body for both `printKotlinFunction` (top-level; `[UInt8]` arrays
    still handled inline since they're top-level only) and the member renderers
    (`renderMethod` / property getters). `appendReturnBody` was deleted.
  - `loweredCdeclForThunk(_:)` (`+SwiftThunkPrinting.swift`) centralizes the
    String?-param / optional-return stripping + lowering; `resolve()` and
    `makeThunkDecl` both call it (this also removed the dual-predicate hazard —
    both now strip via `isOptionalString`).
  - `objectReturnCFunction(lowered:selfParameter:thunkName:)` builds the `void*`
    object-return C signature; used by both `resolve()` (top-level, no self) and
    `memberCFunction` (members, self appended for instances).
- **#7 — dead failable-init guard removed** from `renderConstructor`
  (`memberIsEmittable` already rejects failable inits, since `Self?` doesn't map),
  along with the now-unused `isOptional` helper.

Result: KN unit suite is 105 tests, all green; generated output is byte-identical
(the refactors changed structure, not emitted text).

---

## 6. Later additions

### `[UInt8]` arrays on member methods

Array params and returns are now supported on plain instance and static methods
(not constructors or property accessors, which still use `kotlinParamAndArg`).

**Changes:**

- `memberIsEmittable` (`+Classes.swift`): `allowArrays = (apiKind == .function)`;
  for array return types, strips return to `Void` before the `CdeclLowering` gate
  (array returns use a custom KN ABI, not the standard lowering).
- `renderMethod` (`+Classes.swift`): rewritten to handle array params with
  `usePinned` pinnings and array returns with `memScoped + countVar.ptr`, mirroring
  `printKotlinFunction` for top-level functions.
- `arrayReturningThunk` (`+SwiftThunkPrinting.swift`): now appends `self` parameter
  for instance methods and dispatches the Swift call via `selfParameter` — the same
  dispatch pattern as `nominalAllocatingThunk`.
- `memberCFunction` (`+SwiftThunkPrinting.swift`): new early branch for `.array(.uByte)`
  return — lowers with `Void` return to avoid CdeclLowering failure, then builds a
  custom `CFunction` with `UInt8*` return + out-count param.

**Tests added:** `arrayParam_instanceMethod_kotlin/swiftThunk`,
`arrayReturn_instanceMethod_kotlin/swiftThunk`, `arrayParamAndReturn_instanceMethod_kotlin`,
`arrayReturn_staticMethod_kotlin/swiftThunk` (7 unit tests).

**Sample:** `Counter.accumulate(bytes:)`, `Counter.encoded()`,
`Counter.transform(data:)`, `Counter.zeroBytes(count:)` + 4 integration tests.

---

### Top-level global variables

Swift `public var` declarations at module scope are now emitted as Kotlin `val`
(getter only) or `var` (getter + setter) top-level properties.

**Changes:**

- `NativeGlobalVar` struct + `resolvedGlobalVariables()` cache (main generator):
  reads from `importedGlobalVariables` (not `importedGlobalFuncs`), groups
  getter+setter pairs by name, excludes arrays/optionals/objects.
- `printKotlinGlobalVar()` (main generator): emits `val`/`var` with explicit
  `get()`/`set(value)` blocks using `returnBodyLines` for type-consistent rendering
  (String gets the `free(ptr)` / `toKString()` treatment automatically).
- `writeCinteropHeader` and `writeSwiftThunkSources`: emit C declarations and Swift
  `@_cdecl` thunks for global var accessors. Thunk names follow the same `$get`/`$set`
  convention as member accessors and are backtick-escaped by `cinteropName`.

**Types supported:** all primitives, `Bool`, `Float`, `Double`, `String`. Arrays,
optionals, and custom objects are excluded from global vars (the former two would
need extra ABI machinery; object getters have a top-level vs. member thunk name
ambiguity in `nominalAllocatingThunk`).

**Tests added:** `globalVar_readWrite_kotlin`, `globalVar_readOnly_kotlin`,
`globalVar_string_kotlin`, `globalVar_readWrite_swiftThunk` (4 unit tests).

**Sample:** `globalScore` (read-write `Int`) + `appVersion` (read-only `String`)
globals + 2 integration tests.

---

### Optional params/returns on all member surfaces

Optional types (`Int?`, `Double?`, `String?`, …) are now supported on
constructors, instance/static methods, and property accessors — the same set
as top-level functions.

**Changes:**

- `isMemberType` (`+Classes.swift`): removed `.optional` from the exclusion.
  Optionals were already handled by `kotlinParamAndArg` (params) and
  `returnBodyLines` (returns); the gate was the only blocker.
- `memberIsEmittable` (`+Classes.swift`): the CdeclLowering gate now mirrors
  `loweredCdeclForThunk` exactly — strips `String?` params → `String`, optional
  returns → wrapped type, array returns → `Void` — before passing to
  `CdeclLowering`. Without this, `Optional<String>` params would make the gate
  throw and silently skip the method.
- `memberCFunction` (`+SwiftThunkPrinting.swift`): new optional-return branch
  uses `loweredCdeclForThunk` + custom `CFunction` with `T*`/`char*` return
  (mirrors `resolve()` for top-level functions). The default and object-return
  paths were also switched from raw `CdeclLowering` to `loweredCdeclForThunk`
  so `String?` params are stripped before lowering — fixing a silent C-header
  omission for methods like `func f(s: String?) -> Void`.
- `optionalReturningThunk` + `stringOptionalAwareThunk` (`+SwiftThunkPrinting.swift`):
  both gained self dispatch (same pattern as `arrayReturningThunk`) and the
  getter-access fix (property getters use `obj.prop`, not `obj.prop()`).

**Bugs caught during implementation:**

- `optionalReturningThunk` and `stringOptionalAwareThunk` emitted `obj.value()`
  for optional-returning property getters — same parens bug as the earlier array
  getter fix. Added `isGetter` + `access()` guard to both, locked by a new
  `optionalReturn_propertyGetter_swiftThunk` unit test with a `notExpectedChunks`
  assertion.
- `memberCFunction` was calling raw `CdeclLowering` in its default/object-return
  paths, causing `String?`-param methods to silently vanish from the C header
  (`try?` swallowed the throw). Fixed by switching to `loweredCdeclForThunk`.

**Tests added:** `optionalParam_instanceMethod_kotlin`,
`optionalReturn_instanceMethod_kotlin/swiftThunk`,
`optionalStringReturn_instanceMethod_kotlin`,
`optionalReturn_propertyGetter_kotlin/swiftThunk` (6 unit tests).

**Sample:** `OptionalBox` class (`Int?` constructor + property + methods + `String?`
methods) + 11 integration tests.

---

### Full type support for global variables + `renderPropertyAccessorLines` unification

Global variables now support all types that class properties support — primitives,
`String`, optionals, `[UInt8]`/`UByteArray`, and custom class/struct objects.

**Changes:**

- `resolvedGlobalVariables()`: removed all type exclusions (was excluding `.array`,
  `.optional`, `.object`). Uses `kotlinParamAndArg` for setter info (stores full
  `setterPA` instead of pre-built `setterCallArg` string).
- `nominalAllocatingThunk` (`+SwiftThunkPrinting.swift`): fixed the `default`/no-self
  case to check `isGetter` and omit parens — same parens bug (the fourth occurrence
  across the thunk builders), caught when enabling object-type global vars.
- `renderPropertyAccessorLines` (main generator): new shared function that renders
  `get() { … }` and `set(value) { … }` blocks for any property, parameterised by
  `selfArgs` (`["__ptr()"]` for members, `[]` for globals). Replaced duplicate
  getter/setter rendering in both `renderProperties` and `printKotlinGlobalVar`.
- `NativeGlobalVar` struct: `setterCallArg: String` → `setterPA` (full
  `kotlinParamAndArg` result) so arrays get `usePinned` and optionals get the right
  call expression.

**Tests added:** `globalVar_customObject_kotlin`, `globalVar_optionalInt_kotlin`,
`globalVar_arrayUInt8_kotlin` (3 unit tests); `globalTag`/`globalBytes` sample globals
+ 3 integration tests.

---

### Empty `[UInt8]` array guard

Calling `usePinned { addressOf(0) }` on an empty `UByteArray` throws
`ArrayIndexOutOfBoundsException` in Kotlin/Native. The fix guards the
`addressOf(0)` call inline — `usePinned` still runs unconditionally (it works fine
on empty arrays), but `addressOf(0)` is wrapped in a size check:

```kotlin
data.usePinned { pinned_data ->
    thunk(if (data.size > 0) pinned_data.addressOf(0) else null, data.size.toLong())
}
```

Swift accepts a `nil` `UnsafePointer<UInt8>?` with count 0 as an empty array.

**Change:** `kotlinParamAndArg` (main generator): the `.array` call-arg entry
`"\(pinnedName).addressOf(0)"` changed to
`"if (\(name).size > 0) \(pinnedName).addressOf(0) else null"`.
This is the single source of truth — affects all array param sites: top-level
functions, class methods, constructors, property setters, and global var setters.

---

## 7. Appendix — worked example (the three generated artifacts)

Real `--mode kotlinNative` output for one class and one struct. Swift input
(module `Example`, package `com.example`):

```swift
public class Counter {
  private var count: Int
  public init(start: Int) { count = start }
  public func increment(by amount: Int) { count += amount }
  public func currentValue() -> Int { count }
  public var value: Int {
    get { count }
    set { count = newValue }
  }
  public static func make(start: Int) -> Counter { Counter(start: start) }
}

public struct Point {
  public var x: Int
  public init(x: Int) { self.x = x }
  public func magnitude() -> Int { x }
}
```

### Artifact 1 — Kotlin wrapper (`Example.kt`)

`SwiftHandle` is **no longer emitted inline** — it lives in the `SwiftKitKN` library
(`org.swift.swiftkit.kn`) and is imported. The generated wrapper only holds the
three imports needed for its own body.

```kotlin
// Generated by jextract-swift (kotlinNative mode)
// Swift module: Example
// Calls Swift @_cdecl C thunks directly via Kotlin/Native cinterop

package com.example

import com.example.cinterop.*
import kotlinx.cinterop.*
import platform.posix.free
import org.swift.swiftkit.kn.SwiftHandle
import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.ref.createCleaner

@OptIn(ExperimentalNativeApi::class)
class Counter internal constructor(private val __handle: SwiftHandle) : AutoCloseable {
  private val __cleaner = createCleaner(__handle) { it.destroy() }
  internal fun __ptr(): COpaquePointer = __handle.ensureAlive()
  override fun close() = __handle.destroy()
  constructor(start: Long) : this(SwiftHandle(swiftjava_Example_Counter_init_start(start)!!, ::swiftjava_Example_Counter_destroy))
  fun increment(amount: Long): Unit {
    swiftjava_Example_Counter_increment_by(amount, __ptr())
  }
  fun currentValue(): Long {
    return swiftjava_Example_Counter_currentValue(__ptr())
  }
  var value: Long
    get() {
      return `swiftjava_Example_Counter_value$get`(__ptr())
    }
    set(value) {
      `swiftjava_Example_Counter_value$set`(value, __ptr())
    }
  companion object {
    fun make(start: Long): Counter {
      val ptr = swiftjava_Example_Counter_make_start(start)
      return Counter(SwiftHandle(ptr!!, ::swiftjava_Example_Counter_destroy))
    }
  }
}

@OptIn(ExperimentalNativeApi::class)
class Point internal constructor(private val __handle: SwiftHandle) : AutoCloseable {
  private val __cleaner = createCleaner(__handle) { it.destroy() }
  internal fun __ptr(): COpaquePointer = __handle.ensureAlive()
  override fun close() = __handle.destroy()
  constructor(x: Long) : this(SwiftHandle(swiftjava_Example_Point_init_x(x)!!, ::swiftjava_Example_Point_destroy))
  fun magnitude(): Long {
    return swiftjava_Example_Point_magnitude(__ptr())
  }
  var x: Long
    get() {
      return `swiftjava_Example_Point_x$get`(__ptr())
    }
    set(value) {
      `swiftjava_Example_Point_x$set`(value, __ptr())
    }
}
```

**`SwiftHandle` in `SwiftKitKN`** (`SwiftKitKN/src/macosArm64Main/kotlin/org/swift/swiftkit/kn/SwiftHandle.kt`):

```kotlin
package org.swift.swiftkit.kn

import kotlinx.cinterop.COpaquePointer
import kotlin.concurrent.AtomicInt

public class SwiftHandle(
    private val ptr: COpaquePointer,
    private val destroyFn: (COpaquePointer) -> Unit,
) {
    private val destroyed = AtomicInt(0)

    public fun ensureAlive(): COpaquePointer {
        check(destroyed.value == 0) { "Swift object already destroyed" }
        return ptr
    }

    public fun destroy() {
        if (destroyed.compareAndSet(0, 1)) destroyFn(ptr)
    }
}
```

Things to notice:
- Class and struct produce the **same** wrapper shape (one `SwiftHandle`, `close()`,
  GC cleaner) — the uniform box.
- `SwiftHandle` is now `public` (lives in a separate library), while the wrapper's
  `internal constructor` still restricts construction to the generated module.
- Accessor symbols contain `$` (`value$get`/`x$set`), so the call sites are
  **backtick-escaped**.
- `static func make` lives in `companion object` and, returning a custom type,
  wraps the returned box pointer in a fresh `Counter`/`SwiftHandle`.
- Every call goes through `__handle.ensureAlive()` (throws after `close()`); `self`
  is passed **last**.

### Artifact 2 — cinterop C header (`Example.h`)

```c
// Generated by jextract-swift (kotlinNative mode)
// Plain-C declarations of the Swift @_cdecl thunks for Kotlin/Native cinterop.
#ifndef EXAMPLE_CINTEROP_H
#define EXAMPLE_CINTEROP_H

#include <stddef.h>
#include <stdint.h>

void *swiftjava_Example_Counter_init_start(ptrdiff_t start);
void swiftjava_Example_Counter_increment_by(ptrdiff_t amount, const void *self);
ptrdiff_t swiftjava_Example_Counter_currentValue(const void *self);
void *swiftjava_Example_Counter_make_start(ptrdiff_t start);
ptrdiff_t swiftjava_Example_Counter_value$get(const void *self);
void swiftjava_Example_Counter_value$set(ptrdiff_t newValue, const void *self);
void swiftjava_Example_Counter_destroy(void *pointer);
void *swiftjava_Example_Point_init_x(ptrdiff_t x);
ptrdiff_t swiftjava_Example_Point_magnitude(const void *self);
ptrdiff_t swiftjava_Example_Point_x$get(const void *self);
void swiftjava_Example_Point_x$set(ptrdiff_t newValue, void *self);
void swiftjava_Example_Point_destroy(void *pointer);

#endif
```

Things to notice:
- Init, static factory, and any custom-type return are `void *` (the opaque box).
- `self` and custom-type params are `const void *`; a **mutating** accessor takes
  `void *` (see `Point_x$set` — struct setters mutate through the box).

### Artifact 3 — Swift `@_cdecl` thunks (`ExampleModule+SwiftJava.swift`)

```swift
// Generated by jextract-swift (kotlinNative mode)

import SwiftRuntimeFunctions

@_cdecl("swiftjava_Example_Counter_init_start")
public func swiftjava_Example_Counter_init_start(_ start: Int) -> UnsafeMutableRawPointer {
    let _result = Counter(start: start)
    let _ptr = UnsafeMutablePointer<Counter>.allocate(capacity: 1)
    _ptr.initialize(to: _result)
    return UnsafeMutableRawPointer(_ptr)
}

@_cdecl("swiftjava_Example_Counter_increment_by")
public func swiftjava_Example_Counter_increment_by(_ amount: Int, _ self: UnsafeRawPointer) {
  self.assumingMemoryBound(to: Counter.self).pointee.increment(by: amount)
}

@_cdecl("swiftjava_Example_Counter_currentValue")
public func swiftjava_Example_Counter_currentValue(_ self: UnsafeRawPointer) -> Int {
  return self.assumingMemoryBound(to: Counter.self).pointee.currentValue()
}

@_cdecl("swiftjava_Example_Counter_make_start")
public func swiftjava_Example_Counter_make_start(_ start: Int) -> UnsafeMutableRawPointer {
    let _result = Counter.make(start: start)
    let _ptr = UnsafeMutablePointer<Counter>.allocate(capacity: 1)
    _ptr.initialize(to: _result)
    return UnsafeMutableRawPointer(_ptr)
}

@_cdecl("swiftjava_Example_Counter_value$get")
public func swiftjava_Example_Counter_value$get(_ self: UnsafeRawPointer) -> Int {
  return self.assumingMemoryBound(to: Counter.self).pointee.value
}

@_cdecl("swiftjava_Example_Counter_value$set")
public func swiftjava_Example_Counter_value$set(_ newValue: Int, _ self: UnsafeRawPointer) {
  self.assumingMemoryBound(to: Counter.self).pointee.value = newValue
}

@_cdecl("swiftjava_Example_Counter_destroy")
public func swiftjava_Example_Counter_destroy(_ pointer: UnsafeMutableRawPointer) {
    let typed = pointer.assumingMemoryBound(to: Counter.self)
    typed.deinitialize(count: 1)
    typed.deallocate()
}

@_cdecl("swiftjava_Example_Point_init_x")
public func swiftjava_Example_Point_init_x(_ x: Int) -> UnsafeMutableRawPointer {
    let _result = Point(x: x)
    let _ptr = UnsafeMutablePointer<Point>.allocate(capacity: 1)
    _ptr.initialize(to: _result)
    return UnsafeMutableRawPointer(_ptr)
}

@_cdecl("swiftjava_Example_Point_magnitude")
public func swiftjava_Example_Point_magnitude(_ self: UnsafeRawPointer) -> Int {
  return self.assumingMemoryBound(to: Point.self).pointee.magnitude()
}

@_cdecl("swiftjava_Example_Point_x$get")
public func swiftjava_Example_Point_x$get(_ self: UnsafeRawPointer) -> Int {
  return self.assumingMemoryBound(to: Point.self).pointee.x
}

@_cdecl("swiftjava_Example_Point_x$set")
public func swiftjava_Example_Point_x$set(_ newValue: Int, _ self: UnsafeMutableRawPointer) {
  self.assumingMemoryBound(to: Point.self).pointee.x = newValue
}

@_cdecl("swiftjava_Example_Point_destroy")
public func swiftjava_Example_Point_destroy(_ pointer: UnsafeMutableRawPointer) {
    let typed = pointer.assumingMemoryBound(to: Point.self)
    typed.deinitialize(count: 1)
    typed.deallocate()
}
```

Things to notice:
- **Init / static factory / custom-type return** (`nominalAllocatingThunk`):
  `allocate` → `initialize(to:)` → return the opaque box pointer. Identical shape
  for class (`Counter`) and struct (`Point`).
- **Instance method / getter / setter** reuse the shared `cdeclThunk`: recover
  `self` via `assumingMemoryBound(to: T.self).pointee`, with `self` as the **last**
  parameter.
- **Struct mutating setter** (`Point_x$set`) takes `self` as
  `UnsafeMutableRawPointer` (the shared lowering picks mutable-vs-immutable `self`
  automatically); the class's `value$set` uses `UnsafeRawPointer`.
- **`_destroy`** is one per type: `deinitialize(count: 1)` (ARC release for the
  class; releases reference-typed fields for a struct) then `deallocate()` (frees
  the box). The C symbol uses the flat name; the Swift body uses the qualified type.
