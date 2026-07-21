# Struct Implementation (kotlinNative mode)

Generator sources:
- `KotlinNative/KotlinNativeSwift2KotlinGenerator+Structs.swift` — struct value class + `Inout<Struct>` mutation extensions
- `KotlinNative/KotlinNativeSwift2KotlinGenerator+Classes.swift` — shared member/subscript rendering, `inout` methods
- `KotlinNative/KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` — `@_cdecl` thunks (`inout`, allocating, destroy)

Runtime library (`SwiftKitKN`, package `org.swift.swiftkit.kn`):
- `Inout.kt`, `SwiftCopyable.kt`

---

## 1. The core problem: value semantics over a shared box

A Swift `struct` is a *value type*, however, Kotlin does not have an equivalent. The proposed solution is:

- expose a **read-only class/value class** (`class Point … : SwiftCopyable`) for the
  borrowing surface (getters, non-mutating methods, statics, `copy()`); and
- allow mutations only on `Inout<Struct>` counterparts, so all mutating operations are
  **top-level extensions on `Inout<Struct>`**, not members of the value class.

---

## 2. Runtime support types

### `SwiftCopyable` — every struct wrapper implements it

```kotlin
// SwiftKitKN/.../SwiftCopyable.kt
public interface SwiftCopyable {
    public fun copy(): Any
}
```

Reference types (classes) do **not** implement it — they are shared by reference.

### `Inout<T>` — the uniform mutable / `inout` holder

```kotlin
// SwiftKitKN/.../Inout.kt
public class Inout<T>(value: T, private val onChange: ((T) -> Unit)? = null) {
    private var storedValue: T = copyIfNeeded(value)

    public var value: T                       // value semantics: copy in AND out
        get() = copyIfNeeded(storedValue)
        set(newValue) {
            storedValue = copyIfNeeded(newValue)
            onChange?.invoke(storedValue)
        }

    /** No defensive copy — used by generated marshalling. */
    public var unsafeValue: T
        get() = storedValue
        set(newValue) {
            storedValue = newValue
            onChange?.invoke(newValue)
        }

    @Suppress("UNCHECKED_CAST")
    private fun copyIfNeeded(value: T): T =
        if (value is SwiftCopyable) value.copy() as T else value
}
```

- `value` copies on read **and** write (via `SwiftCopyable.copy()`)
- `unsafeValue` bypasses the copy; outside the generated mutating methods use on your own risk
- For a non-copyable `T` (a primitive or a class wrapper) `copyIfNeeded` is a
  no-op, so `Inout<T>` degrades to a plain box.

---

## 3. The read-only value class

Swift input:

```swift
public struct Point {
  public init(x: Int, y: Int) {}
  public func sum() -> Int { 0 }
}
```

Generated Kotlin (value class — getters, non-mutating methods, `copy()`):

```kotlin
@OptIn(ExperimentalNativeApi::class)
class Point internal constructor(val obj: NSObject) : SwiftCopyable {
  internal fun __ptr(): COpaquePointer = interpretCPointer<CPointed>(obj.objcPtr())!!
  constructor(x: Long, y: Long) : this(wrapSwiftObject { swiftjava_SwiftModule_Point_init_x_y(x, y) })
  fun sum(): Long {
    return swiftjava_SwiftModule_Point_sum(__ptr())
  }
  override fun copy(): Point = Point(wrapSwiftObject { swiftjava_SwiftModule_Point_copy(__ptr()) })
}
```

`printKotlinStruct` (`+Structs.swift:38`) emits: read-only `val` getters,
non-mutating methods, static methods (in a `companion object`), read-only
subscript getters, and the `copy()` override. `wrapSwiftObject` runs the thunk
inside an `autoreleasepool` so the `passRetained(...).autorelease()` +1 balances.

A stored `var x: Int` surfaces read-only on the value class:

```kotlin
val x: Long
  get() {
    return swiftjava_SwiftModule_Point_x_kn_get(__ptr())
  }
```

The corresponding **init thunk** (Swift, box-allocating — uniform for class and
struct, `nominalAllocatingThunk`):

```swift
@_cdecl("swiftjava_SwiftModule_Point_init_x_y")
public func swiftjava_SwiftModule_Point_init_x_y(_ x: Int, _ y: Int) -> UnsafeMutableRawPointer {
    let _result = Point(x: x, y: y) as AnyObject
    return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
}
```

The **copy thunk** (`copyThunk`, `+Structs.swift:300`) raises `self` (a copy, by
value semantics) and boxes a fresh independent `AnyObject`:

```swift
@_cdecl("swiftjava_SwiftModule_Point_copy")
public func swiftjava_SwiftModule_Point_copy(_ self: UnsafeRawPointer) -> UnsafeMutableRawPointer {
    let _result = (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Point) as AnyObject
    return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
}
```

A non-mutating method reads the value from the box with no write-back:

```swift
@_cdecl("swiftjava_SwiftModule_Point_peek")
public func swiftjava_SwiftModule_Point_peek(_ self: UnsafeRawPointer) -> Int {
  return (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Point).peek()
}
```

---

## 4. Mutation: the box-cell `self`

As mentioned before, for mutating methods, the extention on `Inout<Point>` takes the value from the box, 
passes it to swift wrapped in a pointer, then assigns a new value from the passed pointer. Here are the examples:

### 4.1 Settable stored property

Swift:

```swift
public struct Point {
  public var x: Int
  public init(x: Int) { self.x = x }
}
```

Swift thunk (`self` cell in, re-boxed back into the cell, `void` return):

```swift
@_cdecl("swiftjava_SwiftModule_Point_x_kn_set")
public func swiftjava_SwiftModule_Point_x_kn_set(_ newValue: Int, _ self: UnsafeMutableRawPointer) {
    let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
    var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Point
    _self.x = newValue
    self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
}
```

Generated Kotlin — a `var Inout<Point>.x` extension (`renderInoutSetterExtension`):

```kotlin
@OptIn(ExperimentalNativeApi::class)
var Inout<Point>.x: Long
  get() = unsafeValue.x
  set(value) {
    memScoped {
      val self_slot = alloc<COpaquePointerVar>()
      self_slot.value = unsafeValue.__ptr()
      swiftjava_SwiftModule_Point_x_kn_set(value, self_slot.ptr)
      unsafeValue = Point(wrapSwiftObject { self_slot.value })
    }
  }
```

### 4.2 `mutating` method (incl. non-`Void` returns)

Swift:

```swift
public mutating func bump() { x += 1 }
```

Swift thunk:

```swift
@_cdecl("swiftjava_SwiftModule_Point_bump")
public func swiftjava_SwiftModule_Point_bump(_ self: UnsafeMutableRawPointer) {
    let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
    var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Point
    _self.bump()
    self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
}
```

Generated Kotlin — a `fun Inout<Point>` extension (`renderInoutMutatingExtension`):

```kotlin
@OptIn(ExperimentalNativeApi::class)
fun Inout<Point>.bump() {
  memScoped {
    val self_slot = alloc<COpaquePointerVar>()
    self_slot.value = unsafeValue.__ptr()
    swiftjava_SwiftModule_Point_bump(self_slot.ptr)
    unsafeValue = Point(wrapSwiftObject { self_slot.value })
  }
}
```

Because the `self` box rides the cell, the return slot is free, so a **non-`Void`
`mutating` method** works too — scalar *or custom-type* result. Mutating function can also take `inout` parameters

### 4.3 Nested custom-type field: connected holder + scoped mutation

A settable field whose type is itself a custom struct gets **two** mutation
extensions on `Inout<Rect>` (`renderInoutSetterExtension`, `.object` branch), both
reusing `structMutationBlock`.

Swift:

```swift
public struct Point { public var x: Int; public init(x: Int) { self.x = x } }
public struct Rect  { public var topLeft: Point; public init(topLeft: Point) { self.topLeft = topLeft } }
```

Generated Kotlin:

```kotlin
// (1) Connected sub-holder: nested `rect.topLeft.x = …` writes back through the parent.
@OptIn(ExperimentalNativeApi::class)
val Inout<Rect>.topLeft: Inout<Point>
  get() = Inout(unsafeValue.topLeft) { newValue ->
    memScoped {
      val self_slot = alloc<COpaquePointerVar>()
      self_slot.value = unsafeValue.__ptr()
      swiftjava_SwiftModule_Rect_topLeft_kn_set(newValue.__ptr(), self_slot.ptr)
      unsafeValue = Rect(wrapSwiftObject { self_slot.value })
    }
  }

// (2) Scoped batched mutation: read once, mutate in the block, write back once.
@OptIn(ExperimentalNativeApi::class)
fun Inout<Rect>.mutateTopLeft(block: Inout<Point>.() -> Unit) {
  val field = Inout(unsafeValue.topLeft)
  field.block()
  memScoped {
    val self_slot = alloc<COpaquePointerVar>()
    self_slot.value = unsafeValue.__ptr()
    swiftjava_SwiftModule_Rect_topLeft_kn_set(field.unsafeValue.__ptr(), self_slot.ptr)
    unsafeValue = Rect(wrapSwiftObject { self_slot.value })
  }
}
```

Usage differences:

```kotlin
val rect = Inout(Rectangle(Point(0L, 0L), Point(6L, 7L)))

rect.topLeft.value = Point(3L, 9L)   // whole-field replacement
rect.topLeft.x = 3L                  // connected: nested write reaches rect (re-boxes O(depth))
rect.mutateTopLeft {                 // scoped: batched, one write-back, no stale-alias hazard
  x = 10L
  y = 20L
}
```

> **Aliasing caveat**: the connected `rect.topLeft.x = …` path snapshots the field
> on read via the `get()`. Capturing `val t = rect.topLeft`, mutating `rect`
> elsewhere, then writing `t.x` writes back a **stale** snapshot. Use
> `mutateTopLeft { … }` to avoid this.

---

## 5. `inout` parameters (`Inout<T>`)

A Swift `inout T` parameter surfaces as `Inout<T>`. For both primitives and custom types 
the value is boxed into an OpaquePointer, passed to swift, where the updated value is written back into the same box, 
out of which the new value is assigned back to the Kotlin `Inout<T>`.

### 5.1 Primitive `inout` (top-level, `Void`)

Swift: `public func addInPlace(value: inout Int, by amount: Int) { value += amount }`

Kotlin:

```kotlin
fun addInPlace(value: Inout<Long>, amount: Long): Unit {
  memScoped {
    val value_cell = alloc<LongVar>()
    value_cell.value = value.unsafeValue
    swiftjava_SwiftModule_addInPlace_value_by(value_cell.ptr, amount)
    value.unsafeValue = value_cell.value
  }
}
```

Swift thunk (cell is a `void*`; scalar read via `assumingMemoryBound`):

```swift
@_cdecl("swiftjava_SwiftModule_addInPlace_value_by")
public func swiftjava_SwiftModule_addInPlace_value_by(_ value: UnsafeMutableRawPointer, _ amount: Int) {
    var _value = value.assumingMemoryBound(to: Int.self).pointee
    addInPlace(value: &_value, by: amount)
    value.assumingMemoryBound(to: Int.self).pointee = _value
}
```

A non-`Void` return threads through `return memScoped { … ; _result }`:

```kotlin
fun bump(x: Inout<Int>): Boolean {
  return memScoped {
    val x_cell = alloc<IntVar>()
    x_cell.value = x.unsafeValue
    val _result = swiftjava_SwiftModule_bump__(x_cell.ptr)
    x.unsafeValue = x_cell.value
    _result
  }
}
```

### 5.2 Custom-type `inout`

Swift:

```swift
public struct Point { public init() {} }
public func move(p: inout Point) {}
```

Kotlin (cell is a `COpaquePointerVar` holding the box pointer; result re-wrapped):

```kotlin
fun move(p: Inout<Point>): Unit {
  memScoped {
    val p_cell = alloc<COpaquePointerVar>()
    p_cell.value = p.unsafeValue.__ptr()
    swiftjava_SwiftModule_move_p(p_cell.ptr)
    p.unsafeValue = Point(wrapSwiftObject { p_cell.value })
  }
}
```

Swift thunk (raise from the box pointer, mutate, **re-box** into a new
`AnyObject`, write the new pointer back):

```swift
@_cdecl("swiftjava_SwiftModule_move_p")
public func swiftjava_SwiftModule_move_p(_ p: UnsafeMutableRawPointer) {
    let p_box = p.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
    var _p = Unmanaged<AnyObject>.fromOpaque(p_box).takeUnretainedValue() as! Point
    move(p: &_p)
    p.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_p as AnyObject).autorelease().toOpaque()
}
```

---

## 6. Subscripts (`operator fun get` / `set`)

A Swift `subscript` maps to Kotlin `operator fun get`/`set`. `subscriptPairs`
(`+Classes.swift:356`) matches a getter to its setter on the index parameter type
list.

### 6.1 On a class — both accessors are plain members (reference `self`)

Swift: `public subscript(index: Int) -> Int { get { 0 } set {} }`

```kotlin
operator fun get(index: Long): Long {
  return swiftjava_SwiftModule_IntBox_subscript_kn_get(index, __ptr())
}
operator fun set(index: Long, newValue: Long) {
  swiftjava_SwiftModule_IntBox_subscript_kn_set(index, newValue, __ptr())
}
```

### 6.2 On a struct — getter is read-only, setter is an `Inout<Struct>` extension

The getter (borrowing `self`) stays on the value class; the setter mutates, so it
is an `Inout<Struct>` extension using the box-cell `self`
(`renderInoutSubscriptSetterExtension` → `structMutationBlock`):

```kotlin
// value class member
operator fun get(index: Long): Long {
  return swiftjava_SwiftModule_IntArray_subscript_kn_get(index, __ptr())
}

// top-level extension
operator fun Inout<IntArray>.set(index: Long, newValue: Long) {
  memScoped {
    val self_slot = alloc<COpaquePointerVar>()
    self_slot.value = unsafeValue.__ptr()
    swiftjava_SwiftModule_IntArray_subscript_kn_set(index, newValue, self_slot.ptr)
    unsafeValue = IntArray(wrapSwiftObject { self_slot.value })
  }
}
```

The setter thunk indexes `_self[index]` and re-boxes into the `self` cell
(`inoutThunk`, `.subscriptSetter` branch):

```swift
@_cdecl("swiftjava_SwiftModule_IntArray_subscript_kn_set")
public func swiftjava_SwiftModule_IntArray_subscript_kn_set(_ index: Int, _ newValue: Int, _ self: UnsafeMutableRawPointer) {
    let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
    var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! IntArray
    _self[index] = newValue
    self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
}
```

### 6.3 Multi-argument subscript

Swift: `public subscript(row: Int, col: Int) -> Double { get { 0 } set {} }`

```kotlin
operator fun get(row: Long, col: Long): Double {
  return swiftjava_SwiftModule_Matrix_subscript_kn_get(row, col, __ptr())
}
operator fun set(row: Long, col: Long, newValue: Double) {   // class case
  swiftjava_SwiftModule_Matrix_subscript_kn_set(row, col, newValue, __ptr())
}
```

Index parameters may be custom types too (a struct or class key), raised from
their box pointers inside the thunk, exactly like custom-type value parameters.

---

## 7. Swift thunk cheat-sheet

| Operation | Router | Emitter | Signature |
|-----------|--------|---------|-----------|
| init / custom-type return | `case .object?` | `nominalAllocatingThunk` | `void* f(args)` |
| `inout` param / mutable struct `self` (setter, `mutating`, subscript-set) | `needsInoutThunk` | `inoutThunk` | `… f(…, void* self_cell)` |
| struct `copy()` | (per struct) | `copyThunk` | `void* f(self)` |
| per-type cleanup | (per type) | `destroyThunk` | `void f(void*)` |
| everything else | default | shared `cdeclThunk` | lowered FFM ABI |

A mutable struct `self` is an `inout Self` cell — the same lowering as any `inout`
argument — so there is no separate struct-mutation thunk: setters, `mutating`
methods, and subscript setters all flow through `inoutThunk`.

The three artifacts (Kotlin wrapper, C header, Swift thunk) are kept in lockstep:
`memberIsEmittable` is the single gate, and it consults `inoutCdeclSignature` /
`CdeclLowering` so an un-lowerable member is skipped everywhere at once.

---

## 8. End-to-end (from the sample app)

Swift (`SimpleSwiftLib.swift`):

```swift
public struct Point {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public func sum() -> Int { x + y }
    public mutating func scale(by factor: Int) { x *= factor; y *= factor }
    public subscript(index: Int) -> Int {
        get { index == 0 ? x : y }
        set { if index == 0 { x = newValue } else { y = newValue } }
    }
}
public struct Rectangle {
    public var topLeft: Point
    public var bottomRight: Point
    public init(_ topLeft: Point, _ bottomRight: Point) { self.topLeft = topLeft; self.bottomRight = bottomRight }
}
public func recenter(point: inout Point, dx: Int, dy: Int) { /* … */ }
```

Kotlin usage (`SimpleSwiftLibTest.kt`):

```kotlin
import org.swift.swiftkit.kn.Inout

// Read-only value class + copy()
val p = Point(3L, 4L)
assertEquals(7L, p.sum())
val c = p.copy()                      // fresh, independent box

// Mutation through Inout<Point>
val io = Inout(Point(3L, 4L))
io.scale(2L)                          // mutating method
io.x = 100L                           // settable property
io[0L] = 10L                          // subscript setter (Inout extension)
assertEquals(10L, io.value[0L])       // subscript getter (value class)

// Value semantics: Inout(original) stores a copy
val original = Point(1L, 2L)
val held = Inout(original)
held.x = 99L
// original is untouched — held copied on the way in

// inout parameter
val q = Inout(Point(3L, 2L))
recenter(q, 3, 5)

// Nested custom-type field
val rect = Inout(Rectangle(Point(0L, 0L), Point(6L, 7L)))
rect.topLeft.value = Point(3L, 9L)    // whole-field replace
rect.topLeft.x = 3L                   // connected nested write → parent
rect.mutateTopLeft { x = 10L; y = 20L }   // scoped batched write-back
```

---

## 9. Known limitations

- A **non-mutating** (borrowing) struct method that takes an `inout` parameter is
  not surfaced on the value class (the read-only surface has no `inout` marshalling
  path); its thunk is still emitted but unused. `mutating` methods with `inout`
  params *are* supported.
- `String` returns from an `inout`/`mutating` function are still skipped (the inout
  thunk has no C-string marshalling). Scalar, `Void`, and **custom-type** returns
  are all supported.
- `consuming` is not expressible.
- A captured connected sub-holder (`val t = rect.topLeft`) can go stale under
  interleaved parent mutation; use `mutateP { … }` for batched edits.
- `inout String`, and `inout` functions with `String` are skipped.
