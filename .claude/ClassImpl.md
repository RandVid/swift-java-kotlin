# Class / Struct Implementation Across Backends (FFM vs JNI vs Kotlin/Native)

Reference notes on how Swift nominal types (classes & structs) are bridged to
the host language, the ARC accounting involved, and the design plan for adding
class/struct support to **Kotlin/Native (KN)** mode.

---

## 1. FFM mode (Swift → Java) — IMPLEMENTED

### Generated Java wrapper
For each Swift `class`/`struct`/`enum`, jextract emits one `final` Java class that
wraps a pointer into native memory.

Decided in `Sources/JExtractSwiftLib/FFM/FFMSwift2JavaGenerator.swift:387-423`:

```java
public final class MySwiftClass extends FFMSwiftInstance implements SwiftHeapObject { ... }
```

- **Base class:** always `FFMSwiftInstance` (`SwiftKitFFM/.../FFMSwiftInstance.java:22`).
  Error types use `FFMSwiftErrorInstance`.
- **Marker interface** (`FFMSwift2JavaGenerator.swift:402-406`):
  - `class` / `actor` (`isReferenceType`) → `implements SwiftHeapObject`
  - `struct` / `enum` → `implements SwiftValue`
- `@ThreadSafe` added if the Swift type is `Sendable`.

### The instance handle (`self`)
The Java object holds no Swift fields — just a `MemorySegment` + cleanup hook
(`FFMSwiftInstance.java:23-24`):

```java
private final MemorySegment memorySegment;
private final FFMSwiftInstanceCleanup cleanup;
```

`$memorySegment()` (line 43) exposes the pointer, which *is* the Swift `self`.
Every instance method passes it as the trailing native arg, typed
`SwiftValueLayout.SWIFT_POINTER`.

### Type identity & layout
- `TYPE_METADATA` — `SwiftAnyType` fetched by module+name from the Swift runtime.
- `$LAYOUT` — `GroupLayout` from the **value witness table**
  (`SwiftValueWitnessTable.layoutOfSwiftType(...)`), so size/alignment come from
  Swift itself.

### Construction
- `wrapMemoryAddressUnsafe(segment, arena)` — wraps an existing pointer
  without copy/retain (the retain already happened in the thunk).
- Initializers & factories become **static methods** taking an
  `AllocatingSwiftArena`. They allocate `$LAYOUT` from the arena, call the
  native init thunk writing into `_result`, then wrap.

### Generated Swift thunks (FFM)
From `Samples/SwiftJavaExtractFFMSampleApp/.build/.../MySwiftClass+SwiftJava.swift`:

```swift
// type metadata accessor
@_cdecl("swiftjava_getType_MySwiftLibrary_MySwiftClass")
public func ...() -> UnsafeMutableRawPointer { unsafeBitCast(MySwiftClass.self, to: UnsafeMutableRawPointer.self) }

// init — caller-allocated indirect return (_result)
@_cdecl("swiftjava_MySwiftLibrary_MySwiftClass_init_len_cap")
public func ...(_ len: Int, _ cap: Int, _ _result: UnsafeMutableRawPointer) {
  _result.assumingMemoryBound(to: MySwiftClass.self).initialize(to: MySwiftClass(len: len, cap: cap))
}

// instance method / accessor — self: UnsafeRawPointer recovered via .pointee
@_cdecl("swiftjava_MySwiftLibrary_MySwiftClass_voidMethod")
public func ...(_ self: UnsafeRawPointer) {
  self.assumingMemoryBound(to: MySwiftClass.self).pointee.voidMethod()
}
```

- Return lowering: `FunctionLowering.swift:809-820` (`.populatePointer(assumingType:to:.placeholder)`).
- Renders to `initialize(to:)` via `ConversionStep.swift:150-158`.
- **No generated `_destroy` thunk** — destruction is done on the Java side via
  `SwiftValueWitnessTable.destroy(type, ptr)`.

### class vs struct in FFM
Structurally identical (both extend `FFMSwiftInstance`, both arena-managed).
Divergence:

| | `class` (reference) | `struct`/`enum` (value) |
|---|---|---|
| Interface | `SwiftHeapObject` | `SwiftValue` |
| Cleanup | Swift ARC release (`swift_release`) | value-witness `destroy` |
| Retain/release API | `SwiftRuntime.retain/release/retainCount` | n/a |

**Why FFM unifies on the buffer:** a struct *must* live as real bytes in
addressable memory, so the buffer+value-witness path has to exist anyway;
reusing it for classes means one code path, not two. Java only knows the type
as runtime metadata (no static `T`), so it *must* go through the VWT.

---

## 2. ARC accounting (FFM)

There is no explicit "register with ARC" call. The object's retain count is a
single integer in its heap header. "Registering Java as an owner" = that count
ends up +1, with the Java-owned buffer holding that reference.

**The +1 (return path):**
1. The Swift function returns the object at **+1** (caller-owned by convention —
   for an existing object the compiler emits a `swift_retain` before returning).
2. `initialize(to:)` **moves** that +1 into the buffer (strong store; no extra retain).
3. The thunk returns; the scope-end release is suppressed because the reference
   now lives in persistent memory. The buffer is now an independent strong owner.

**The −1 (cleanup path):**
- `FFMSwiftInstance` constructor calls `arena.register(this)`
  (`FFMSwiftInstance.java:32-37`) — Java-side bookkeeping that it *owes* a −1.
- On arena close / GC (auto arena), `FFMSwiftInstanceCleanup.run()` (CAS-guarded
  `destroyed` flag) calls `SwiftValueWitnessTable.destroy(type, ptr)` →
  value-witness `destroy` → `swift_release` (−1).

**Two distinct registrations:**
- ARC registration (Swift heap): retain count +1, via the `initialize(to:)` store.
- Cleanup registration (Java heap): `arena.register(this)`, guarantees the −1.

**Lifetime model:** liveness is tied to the **arena**, not JVM reachability.
- `SwiftArena.ofAuto()` → release driven by JVM GC (via `Cleaner`), non-deterministic.
- `SwiftArena.ofConfined()` + `try (...)` → release at scope exit, deterministic.
- After release, `$ensureAlive()` throws on further calls.

---

## 3. JNI mode (Swift → Java) — IMPLEMENTED

JNI is the *other* Swift→Java backend (older-JDK / Android compatible). It bridges
classes/structs too, but — unlike FFM — it uses **Option B** allocation (Swift
allocates; see §6): the host holds an opaque `long`, never a layout-aware buffer.

### Generated Java wrapper
`Sources/JExtractSwiftLib/JNI/JNISwift2JavaGenerator+JavaBindingsPrinting.swift:444-453`:

```java
public final class MySwiftClass implements JNISwiftInstance {   // interface, NOT a base class
  private final long selfPointer;                 // self handle is a plain long
  private final SwiftInstanceCleanup $cleanup;
  public long $memoryAddress() { return this.selfPointer; }
}
```
- `JNISwiftInstance` is an **interface** (`SwiftKitCore/.../JNISwiftInstance.java`),
  vs FFM's abstract base `FFMSwiftInstance`.
- Self is a raw `long` address — **no `MemorySegment`, no `$LAYOUT`, no VWT-in-Java**.
- Constructor `(long selfPointer[, long selfTypePointer], SwiftArena swiftArena)`
  validates non-zero, builds `$cleanup = $createCleanup()`, `swiftArena.register(this)`
  (`:273-290`) — same arena model as FFM.
- `wrapMemoryAddressUnsafe(long[, SwiftArena])` (`:305-311`), same "does not copy/retain" doc.
- Generics also store `long selfTypePointer` (the type-metadata address).

### Allocation & self (Swift-side)
- Init/factory thunks **allocate in Swift and return the address as a `jlong`** —
  via the `allocateSwiftValue` conversion (`+NativeTranslation.swift:1476-1491`):
  `UnsafeMutablePointer<T>.allocate(capacity: 1); pointer.initialize(to: …)`.
  Java never allocates; never needs the layout.
- Instance-method thunks take `self` as a `jlong`, reconstitute the pointer, use
  `.pointee` (`+SwiftThunkPrinting.swift:1067-1086`):
  `UnsafeMutablePointer<T>(bitPattern: selfPointerBits$)!` then `.pointee.method(...)`.
- Uniform for class & struct (same `allocate` + `initialize`).

### ARC / destroy
- **+1** is the same `initialize(to:)` strong store as FFM.
- **−1** is NOT a Java VWT reimplementation (FFM) nor a per-type destroy thunk (the
  KN plan). It's a single **shared native** `SwiftObjects.destroy(memoryAddress, typeMetadataAddress)`
  (`SwiftObjects.java:30` — `public static native void destroy(long, long)`), built by
  `JNISwiftInstance.$createDestroyFunction()` (`JNISwiftInstance.java:30-50`) and fed by
  a per-type `$typeMetadataAddress()` thunk (`unsafeBitCast(T.self, …)`). So destroy is
  metadata-driven but executed in the **Swift runtime**, not reimplemented in Java.
- Once-only via CAS-guarded `JNISwiftInstanceCleanup` (`JNISwiftInstanceCleanup.java:39`);
  lifetime via `SwiftArena` — same shape as FFM.

### FFM vs JNI (Option A vs Option B)
Same host *language* (Java), **opposite** allocation choice — proving the pick is
about the FFI primitive, not the language:

| | FFM (Option A) | JNI (Option B) |
|---|---|---|
| Wrapper base | `extends FFMSwiftInstance` | `implements JNISwiftInstance` |
| Self handle | `MemorySegment` | `long` |
| **Allocator** | **Java** (`arena.allocate($LAYOUT)`) | **Swift thunk** |
| Needs `$LAYOUT` / VWT-in-Java? | yes | **no** |
| Init thunk | fills caller's `_result` (sret), returns void | allocates, returns address (`jlong`) |
| Cross-boundary call | Panama `MethodHandle` downcall | JNI `native` method |
| `self` in thunk | `.pointee` on passed pointer | `bitPattern:` → `.pointee` |
| Destroy | Java VWT `destroy(type, ptr)` | shared native `SwiftObjects.destroy(ptr, typeMeta)` |
| Metadata needed for destroy | yes (`SwiftAnyType`) | yes (`$typeMetadataAddress`) |
| By-value struct semantics | yes (layout-aware) | no (opaque handle) |

**Takeaway:** FFM is the outlier among the three backends. Both **JNI and KN use
Option B** (Swift allocates, host layout-blind). JNI proves Option B already ships on
the JVM — making it the **closer structural template** for the KN class/struct work
than FFM (opaque handle + Swift-side alloc/init + arena/CAS cleanup ≈ `COpaquePointer`
+ `createCleaner`/`AutoCloseable`). The one fork: JNI destroys via a shared
metadata-driven native (needs a per-type metadata thunk), whereas the KN plan uses
per-type `_destroy` thunks (no metadata — `swiftc` has static `T`).

---

## 4. Kotlin/Native mode — mechanism (top-level funcs only today)

KN is a **completely different** architecture from FFM: pure **C ABI + cinterop**,
no JVM, no FFM, no `MemorySegment`, no `SwiftArena`, no value witness table.

1. Swift side emits `@_cdecl` thunks with C signatures
   (`<Module>Module+SwiftJava.swift`).
2. A `.def` file points KN's `cinterop` tool at a generated C header → bindings
   in package `<pkg>.cinterop`.
3. Generated Kotlin wrappers call those cinterop functions directly.

Generator: `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift`
(+ `+SwiftThunkPrinting.swift`). Reuses the shared `CdeclLowering` and
`ThunkNameRegistry` from the FFM path for signatures/symbol names.

### Current scope (branch state)
**Top-level functions only.** Both the resolver
(`KotlinNativeSwift2KotlinGenerator.swift:145-147`) and the thunk emitter
(`+SwiftThunkPrinting.swift:64-67`) hard-gate on:

```swift
guard decl.apiKind == .function, decl.hasParent == false, decl.isAsync == false else { ... }
```

Supported types: `Int/Int8/16/32/64`, `UInt/8/16/32/64`, `Bool`, `Float`,
`Double`, `Void`; `String` (params + returns); and custom class/struct types.

### NOT implemented for KN
- Classes / structs / any nominal-type wrapper. Members are skipped
  (`hasParent == false`).
- No use of `Unmanaged` / `passRetained` / `fromOpaque` anywhere in
  `Sources/JExtractSwiftLib/KotlinNative/` (only the FFM error path at
  `FunctionLowering.swift:1093` uses `passRetained`).

---

## 5. DESIGN DECISION — class/struct support in KN

### Chosen approach: uniform thunk-allocated box + `.pointee`
Because **structs will also be implemented**, go uniform (same rationale FFM
used). `Unmanaged` cannot represent a struct (`AnyObject`-only), so a box path is
required anyway — and a single box path handles both kinds with **no
`isReferenceType` branch**.

```swift
// init — thunk allocates, returns opaque pointer (works for class AND struct)
@_cdecl("..._T_init_…")
public func ...(...) -> UnsafeMutableRawPointer {
  let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
  p.initialize(to: T(...))                       // class: strong store → retain. struct: copy in.
  return UnsafeMutableRawPointer(p)
}

// method / accessor — self: UnsafeRawPointer + .pointee (IDENTICAL to FFM)
@_cdecl("..._T_method_…")
public func ...(_ self: UnsafeRawPointer, ...) -> R {
  return self.assumingMemoryBound(to: T.self).pointee.method(...)
}

// destroy — statically correct for both; NEW for KN
@_cdecl("..._T_destroy")
public func ...(_ p: UnsafeMutableRawPointer) {
  let tp = p.assumingMemoryBound(to: T.self)
  tp.deinitialize(count: 1)                      // class: release. struct: release members.
  tp.deallocate()                                // frees the box (NOT the object)
}
```

### Why NOT port FFM's caller-allocated `.pointee` + VWT
- FFM makes the *caller* allocate → needs the layout → needs the value-witness
  runtime. KN has none of that runtime.
- KN's advantage: thunks are generated **in Swift with static `T`**, so it can
  express size (`MemoryLayout<T>.stride`) and destroy (`deinitialize`) directly
  — no runtime metadata reflection needed.
- Letting the **thunk** allocate (not the caller) removes the need for a `sizeof`
  thunk or Kotlin-side layout knowledge.

### Why NOT `Unmanaged`-everywhere
- Classes-only → `Unmanaged` is leanest (object's own address as handle, no box).
- But with structs in scope, you'd need a second path → two code paths. Uniform
  box = one path.
- Reserve `Unmanaged` as a **later, optional specialization for classes** only if
  zero-overhead class calls or pointer identity become real requirements.

### Costs of the box approach (accepted)
- One extra small allocation + one `.pointee` indirection per **class** call
  (negligible).
- Pointer identity not preserved: same object returned twice → two distinct
  handles. (FFM has the same behavior — parity, not regression.) If identity
  matters, add a `pointer → wrapper` cache; note `Unmanaged`'s stable
  object-address handle makes such a cache natural, the box's per-call address
  does not.

### Kotlin wrapper shape
Thin handle over a `COpaquePointer`, lifetime via `createCleaner` (GC-backed,
≈ FFM auto arena) **or** `AutoCloseable` + `use {}` (deterministic, ≈ confined
arena). Guard destroy with a CAS `AtomicInt` (≈ FFM's `destroyed` flag) and an
`$ensureAlive()`-style check. Call the `_destroy` thunk on cleanup — do **not**
`free()` the handle directly (nominal types need the Swift-side `deinitialize`).

---

## 6. Allocation tradeoff: host-allocates vs Swift-malloc delegation

When a Swift nominal value crosses to the host, *someone* must allocate the
storage that holds it. There are two implementable strategies, and the choice is
what ultimately decides whether the backend needs the VWT:

- **(A) Host allocates** the buffer, passes a pointer in; the Swift thunk
  initializes into it (this is Swift's native *indirect return* / `sret` ABI).
- **(B) Swift thunk allocates** (`UnsafeMutablePointer<T>.allocate`) and returns
  an opaque pointer the host just holds.

Both are possible in *both* languages. Each backend picks the one matching its
host platform's native FFI primitive.

### FFM (Java)

**Option A — Java allocates → CHOSEN**
- *Impl:* `MemorySegment seg = arena.allocate(T.$LAYOUT);` then
  `thunk(args, seg)` where the thunk does
  `seg.assumingMemoryBound(to: T.self).initialize(to: T(...))`. Destroy on the
  Java side via `SwiftValueWitnessTable.destroy(type, seg)`.
- *Pros:*
  - Matches Swift's native indirect-return ABI (caller supplies the result slot)
    → one downcall, value constructed in place, **no extra box/copy**.
  - Layout-aware `MemorySegment` enables **by-value struct semantics**: direct
    field access via `VarHandle`, passing a struct by value to other Swift calls,
    embedding in aggregates.
  - Integrates with the arena + `Cleaner` + bounds-checked/lifetime-tracked
    `MemorySegment`; uniform with how FFM handles params / arrays / `Data`.
- *Cons:*
  - Needs the type layout at runtime (`$LAYOUT`) → **requires the VWT**
    (`layoutOfSwiftType`) + Swift runtime metadata reimplemented in Java
    (`SwiftValueWitnessTable.java`, `SwiftAnyType`).

**Option B — delegate to Swift malloc → NOT chosen**
- *Impl:* thunk does
  `let p = UnsafeMutablePointer<T>.allocate(capacity: 1); p.initialize(to: T(...)); return UnsafeMutableRawPointer(p)`;
  Java wraps via `MemorySegment.ofAddress(addr)` (unbounded) and frees via a
  destroy thunk.
- *Pros:* Java wouldn't need layout → could drop the VWT-for-layout.
- *Cons:*
  - Extra heap allocation + copy on every return (a box separate from the `sret`
    slot); deviates from Swift's return ABI.
  - Opaque pointer can't support by-value composition / field access → loses
    FFM's richer value model.
  - Unbounded `MemorySegment` loses bounds/lifetime safety; breaks the
    arena/MemorySegment uniformity.
  - **Wouldn't even save the VWT** in practice: FFM still wants layout for
    by-value handling and routes cleanup through its uniform type-erased VWT
    destroy.
- *Why rejected:* the JVM Panama platform is built around layout-aware segments;
  FFM leans in to get ABI-native returns + value semantics + a uniform safe-memory
  model. The VWT layout query is "paid for" by those gains.

### JNI (Java, via JNI) — Option B, SHIPPING

Same host *language* as FFM, but the **opposite** choice — because JNI's FFI
primitive is a `jlong` / `native` call, not a layout-aware `MemorySegment`.
- *Impl:* the Swift thunk allocates (`UnsafeMutablePointer<T>.allocate` +
  `initialize(to:)`) and returns the address as a `jlong`; Java holds it as
  `long selfPointer` and never queries layout. Destroy via the shared native
  `SwiftObjects.destroy(addr, typeMeta)`. (Full details in §3.)
- *Why it's Option B:* JNI can only shuttle primitives across the boundary, so it
  can't hold or compose a layout-aware buffer — exactly KN's situation. It therefore
  delegates allocation to Swift and stays layout-blind.
- *Significance:* JNI is a **shipping proof** that Option B works on the JVM, and
  makes **FFM the outlier** — the only backend that chooses host-allocation, forced
  by Panama's layout-aware-segment model.

### KN (Kotlin)

**Option A — Kotlin allocates → NOT chosen**
- *Impl:* Kotlin `nativeHeap.alloc` / `memScoped` a buffer of size `N`, pass the
  pointer to an init thunk that does `initialize(to:)`. Requires `N`.
- *Pros:* symmetric with FFM; caller owns the memory.
- *Cons:*
  - Kotlin must know the **size** → jextract can't compute ABI sizes statically
    (it analyzes source; resilient types' size is runtime/version-dependent) →
    would need a generated `sizeof` thunk per type, OR a VWT-equivalent in KN.
  - KN has **no VWT runtime** → you'd have to build metadata-walking machinery —
    exactly what we want to avoid.
  - More host-side complexity for zero benefit (KN exposes no by-value composition).
- *Why rejected:* reintroduces the layout/size machinery KN deliberately lacks.

**Option B — delegate to Swift malloc → CHOSEN**
- *Impl:* thunk
  `let p = UnsafeMutablePointer<T>.allocate(capacity: 1); p.initialize(to: T(...)); return UnsafeMutableRawPointer(p)`.
  Kotlin holds the opaque `COpaquePointer`. Destroy via a generated `_destroy`
  thunk (`deinitialize(count: 1)` + `deallocate()`); host lifetime via
  `createCleaner` / `AutoCloseable`.
- *Pros:*
  - Host stays fully **layout-blind** — opaque handle like a C `FILE*`; no size
    query, no VWT, no `sizeof` thunk.
  - All type-dependent logic (alloc / init / destroy) stays in Swift, where
    `swiftc` has static `T`.
  - Fits cinterop's opaque-C-pointer model and KN's `Cleaner`/`AutoCloseable`
    lifetime model.
- *Cons:*
  - One extra small allocation (box) + one `.pointee` indirection per call
    (negligible).
  - No by-value composition / direct field access from Kotlin (acceptable — not a
    KN goal).
  - Per-object destroy (no bulk free); pointer identity not preserved (see §5).
- *Why chosen:* KN has no layout machinery and an opaque-pointer host model;
  Swift-allocates keeps the host dumb and needs nothing the FFM VWT provides.

### Deciding principle
**Who allocates follows from the lifetime model, which follows from the host
platform's native FFI primitive:**

| | FFM / JVM Panama | JNI / JVM JNI | KN / cinterop |
|---|---|---|---|
| Host primitive | layout-aware `MemorySegment` | `jlong` + `native` call | opaque `void*` |
| Allocator | **host (Java, via arena)** | Swift thunk | Swift thunk |
| Return convention | indirect return (caller's buffer) | thunk allocates, returns `jlong` | thunk allocates, returns pointer |
| Host needs layout? | yes → **VWT** | no | no |
| Value semantics | by-value structs, field access, composition | none — opaque handle | none — opaque handle |
| Destroy | Java VWT `destroy(type, ptr)` | shared native, metadata-driven | per-type `_destroy` thunk (planned) |
| Trade paid | runtime layout machinery (VWT) | per-object alloc + metadata thunk | per-object boxing |

**FFM is the lone Option A** — the only backend that allocates host-side, forced by
Panama's layout-aware-segment model. JNI and KN both choose Option B. All three are
implementable in either language; the pick follows the host platform's FFI primitive,
not the language (FFM and JNI are *both* Java, yet land on opposite choices).

---

## 7. Reusing FFM thunks for KN — what ports

| Thunk kind | Reuse FFM? |
|---|---|
| Methods / getters / setters / subscripts | **Yes** — same `CdeclLowering` + `cdeclThunk`, identical output. `self: UnsafeRawPointer` + `.pointee` is exactly what the box gives. KN already feeds `selfParameter` into its lowering (`KotlinNativeSwift2KotlinGenerator.swift:221`); just open the `hasParent` gate for members. |
| Init / factory | Body yes (`initialize(to: T(...))`), shape no — write a custom thunk-allocating emitter (`nominalAllocatingThunk` in `+SwiftThunkPrinting.swift`). |
| Destroy | **New** — `deinitialize(count: 1)` + `deallocate()`. |
| `getType` metadata | **Not needed** (no VWT/runtime metadata path in KN). |

Bonus: the shared lowering already picks `UnsafeRawPointer` vs.
`UnsafeMutableRawPointer` for `self` based on `mutating`/setter semantics — so
struct mutating methods/setters are handled for free.

Implementation note: the `hasParent == false` gate in BOTH
`KotlinNativeSwift2KotlinGenerator.swift` and `+SwiftThunkPrinting.swift` is
exactly where to branch to a nominal-type path.

---

## 8. Pointer lifecycle methods (Swift stdlib)

These are **Swift standard library members of `UnsafeMutablePointer<Pointee>`** —
not defined in this repo.

```
allocate()          initialize(to:)        deinitialize(count:)   deallocate()
   │                      │                      │                    │
   ▼                      ▼                      ▼                    ▼
[ raw ] ───────────▶ [ initialized ] ──────▶ [ raw ] ────────────▶ [ freed ]
 garbage bytes        holds a valid T        garbage again         gone
```

| Method | What it does |
|---|---|
| `static allocate(capacity:)` | reserve raw, uninitialized heap memory |
| `initialize(to:)` | construct a value into raw memory (strong store; takes ownership) |
| `deinitialize(count:)` | run the value's destroy (release owned refs), back to raw |
| `deallocate()` | return raw memory to the allocator |

Pairs: `allocate ↔ deallocate` (raw memory), `initialize ↔ deinitialize`
(value lifetime, nested inside). **Teardown order: `deinitialize` THEN `deallocate`.**

### `initialize` vs `=` (assignment) — critical
- raw memory → use **`initialize(to:)`** (does NOT release prior contents).
- already-initialized memory → use **assignment** (releases old + retains new),
  e.g. property setters' `.pointee.len = newValue`.
- `p.pointee = v` on freshly-`allocate`d (raw) memory → tries to release garbage
  → **crash/corruption**.

### Existing usages in repo
- `Sources/SwiftJavaRuntimeSupport/JextractedTypeBridge.swift:28-29` —
  `allocate(capacity: 1)` + `initialize(to: value)` (the boxing idiom).
- KN box-allocating thunk: `nominalAllocatingThunk` in `+SwiftThunkPrinting.swift`.
- FFM class init via `ConversionStep.swift:158`.
- `deinitialize` / `deallocate`: **not yet used** anywhere in the generators
  (would be new, for the KN `_destroy` thunk).

Reference: https://developer.apple.com/documentation/swift/unsafemutablepointer

---

## 9. ARC semantics summary (mental model)

**Per slot, balanced 1:1:** `initialize(to:)` leaves the slot owning one strong
reference; `deinitialize(count:)` gives it up. Precisions:

1. "Strong reference" only exists if `Pointee` holds references:
   - **class** → exactly one strong ref (+1) per slot.
   - **trivial type** (`Int`, `Double`…) → none; `initialize` is a byte store,
     `deinitialize` a no-op.
   - **struct with reference members** → one strong ref *per* reference-typed
     field (can be N, not 1).
2. Must be exactly 1:1 per slot:
   - double `initialize` without `deinitialize` between → **leak**.
   - double `deinitialize` → **over-release / crash**.
3. The +1 may be **moved in** (the value arrived at +1) rather than a fresh
   retain; `initialize(to: someVar)` *does* insert a retain. Either way the
   slot's books are +1 after init, 0 after deinit.

**Returning an existing object:** works automatically — the +1 return convention
retains pre-existing objects too, so the box/buffer becomes an independent owner;
other Swift owners keep the object alive after the box's −1. Watch:
- **class** → box references the SAME object (shared identity & mutations).
- **struct** → `initialize(to:)` stores an independent COPY (value semantics).
- No handle dedup (same object twice = two wrappers, two releases).
- **Never** hand out a `+0` / `passUnretained` reference across the boundary —
  the foreign side must be a real owner or it dangles when Swift releases.

**`deallocate()` frees the box, never an object alive elsewhere.** For a class
the object is independently refcounted; `deinitialize` drops only the box's
reference, ARC frees the object at count 0. The real hazard is the inverse:
using/destroying the handle from the host side after destroy → use-after-free /
double-free. Mitigate with: destroy-exactly-once (CAS guard), no-calls-after-
destroy (`$ensureAlive`), and correct teardown order.
