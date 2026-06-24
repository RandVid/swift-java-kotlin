# Theoretical: Generalising Array Support to All Primitive Element Types

## Short Answer

Yes — feasible, and mostly mechanical. `KotlinType` already models `array(KotlinType)` for
any element; the only reason only `[UInt8]` works today is a series of hardcoded `.uByte`
guards in four files. The overall ABI shape (heap-pointer + out-count for returns,
`usePinned { addressOf(0) }` for parameters) is the same for every primitive element type.

---

## What Already Works Without Changes

- `KotlinType.array(KotlinType)` — the enum case is generic; no structural change needed.
- `usePinned { pinned.addressOf(0) }` — pins any typed Kotlin array; element-agnostic.
- `CdeclLowering` for **parameters** — already lowers any `[T]` to `(UnsafeRawPointer, Int)`;
  the raw-pointer pair is the same regardless of element width.
- `arrayReturningThunk` body logic — `withUnsafeBytes` + `UnsafeMutablePointer.allocate` +
  `initialize(from:count:)` is element-agnostic; only the type annotations need parameterising.

---

## What Needs Changing (four files)

### 1. `swiftTypeToKotlin()` — remove the `.uByte` guard
`Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift`

```swift
// current — rejects every array except [UInt8]
case .array(let element):
    if let inner = swiftTypeToKotlin(element), inner == .uByte { return .array(.uByte) }
    return nil

// generalised
case .array(let element):
    if let inner = swiftTypeToKotlin(element) { return .array(inner) }
    return nil
```

Also extend the string-fallback branch to recognise `"[Int]"`, `"[Double]"`, etc.

### 2. `resolve()` — generalise the return ABI builder
`Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift`

Change `case .array(.uByte)` to `case .array(let elementKt)` and look up the matching Swift
pointer type from the table below to build the custom `CFunction` (return type, count param).

### 3. `printKotlinFunction()` — parameterise array-return code generation
`Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift`

Today hardcodes `ByteVar`, `reinterpret<ByteVar>()`, `.asUByteArray()`. Need a small helper
that maps, e.g., `.array(.long)` → `("LongVar", "LongArray")`.

**One non-trivial bit:** `readBytes(count)` reads `count` **bytes**, not elements. For wider
types the Kotlin reconstruction must use typed element access:

```kotlin
// [UInt8] today
ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()

// [Int] / LongArray — count is element count, step by element
LongArray(count) { i -> ptr.reinterpret<LongVar>()[i] }
```

### 4. `arrayReturningThunk()` — parameterise Swift element type
`Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift`

Currently uses `[UInt8]` and `UnsafeMutablePointer<UInt8>` literally. Pass the Swift element
type string (`"UInt8"`, `"Int"`, `"Double"`, …) as a parameter; the copy logic stays the same.

### 5. `KotlinType.description` — add named array types
`Sources/JExtractSwiftLib/Kotlin/KotlinType.swift`

Only `UByteArray` has a named form today; all others fall back to `Array<T>`. Add cases for
`IntArray`, `LongArray`, `FloatArray`, `DoubleArray`, `ByteArray`, `ShortArray`, etc.

---

## Element-Type Mapping Table

| Swift type  | `KotlinType`       | Kotlin Var   | Kotlin Array  | Swift element | C return type |
|-------------|--------------------|--------------|---------------|---------------|---------------|
| `[UInt8]`   | `.array(.uByte)`   | `UByteVar`   | `UByteArray`  | `UInt8`       | `uint8_t*`    |
| `[Int]`     | `.array(.long)`    | `LongVar`    | `LongArray`   | `Int`         | `ptrdiff_t*`  |
| `[Int32]`   | `.array(.int)`     | `IntVar`     | `IntArray`    | `Int32`       | `int32_t*`    |
| `[Int8]`    | `.array(.byte)`    | `ByteVar`    | `ByteArray`   | `Int8`        | `int8_t*`     |
| `[Int16]`   | `.array(.short)`   | `ShortVar`   | `ShortArray`  | `Int16`       | `int16_t*`    |
| `[Int64]`   | `.array(.long)`    | `LongVar`    | `LongArray`   | `Int64`       | `int64_t*`    |
| `[UInt]`    | `.array(.uLong)`   | `ULongVar`   | `ULongArray`  | `UInt`        | `size_t*`     |
| `[UInt32]`  | `.array(.uInt)`    | `UIntVar`    | `UIntArray`   | `UInt32`      | `uint32_t*`   |
| `[UInt16]`  | `.array(.uShort)`  | `UShortVar`  | `UShortArray` | `UInt16`      | `uint16_t*`   |
| `[Float]`   | `.array(.float)`   | `FloatVar`   | `FloatArray`  | `Float`       | `float*`      |
| `[Double]`  | `.array(.double)`  | `DoubleVar`  | `DoubleArray` | `Double`      | `double*`     |
| `[Bool]`    | *(skip)*           | —            | —             | —             | —             |

`[Bool]` is excluded: `Boolean` has no `BooleanVar` in Kotlin/Native cinterop — no addressable
numeric type to pin against.

`[Int]` and `[Int64]` both map to `LongArray` since Swift `Int` is 64-bit on all Apple
platforms; they can share the same `KotlinType` (`.array(.long)`).

---

## Effort

Small-to-medium. Four files, all changes additive and driven by the table above. No architectural
restructuring needed. Tests follow the exact same pattern as existing `[UInt8]` tests.
