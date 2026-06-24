# Optional Type Support in Kotlin/Native Generator

This document describes the implementation of Swift optional types (`T?`) in
`KotlinNativeSwift2KotlinGenerator` — both as function parameters and as return types, covering
numeric primitives, booleans, floats, and `String`.

## Overview

Kotlin natively supports nullable types (`T?`), so Swift optionals map cleanly to Kotlin nullable
types. The challenge is the C ABI layer between Swift and Kotlin/Native:

- **Optional parameters** — a null pointer means the value is absent; a valid pointer means it is
  present.
- **Optional returns** — the Swift thunk heap-allocates the result and returns a pointer, returning
  null if the Swift function returned `nil`. The Kotlin wrapper must free the pointer after copying.
- **String** — requires its own handling because `String` is not a C-compatible type; it is passed
  and returned as a null-terminated C string (`char*`), so `String?` needs a dedicated nullable
  pointer strategy.

The work was delivered in two phases:

| Phase | Scope |
|-------|-------|
| 1 | Optional parameters: `Int?`, `Int32?`, `Bool?`, `Double?`, unsigned variants |
| 2 | Optional returns of the same types, plus `String?` as both parameter and return |

---

## Supported Types

| Swift type | Kotlin type | Notes |
|------------|-------------|-------|
| `Int?` | `Long?` | 64-bit signed |
| `Int32?` | `Int?` | 32-bit signed |
| `Int16?` | `Short?` | |
| `Int8?` | `Byte?` | |
| `UInt?` | `ULong?` | 64-bit unsigned |
| `UInt32?` | `UInt?` | |
| `UInt16?` | `UShort?` | |
| `UInt8?` | `UByte?` | |
| `Bool?` | `Boolean?` | |
| `Float?` | `Float?` | |
| `Double?` | `Double?` | |
| `String?` | `String?` | Separate ABI — see §String |

`Optional<Array>` and nested optionals (e.g., `Int??`) are not supported and are skipped with a
comment.

---

## Phase 1: Optional Parameters

### ABI

The shared FFM lowering (`lowerOptionalParameter` in
`FFMSwift2JavaGenerator+FunctionLowering.swift`) lowers a `T?` parameter where `T` has a 1:1 C
representation to `UnsafePointer<T>?` (nullable pointer). The C declaration is therefore:

```c
// Swift: func fn(x: Int?) -> Void
void swiftjava_Module_fn(const ptrdiff_t* x);
```

A null pointer means the argument was absent; a valid pointer means the caller stored the value at
that address.

### Swift thunk

The shared `cdeclThunk` path handles optional parameters correctly — no custom thunk is needed.
The generated thunk:

```swift
@_cdecl("swiftjava_Module_fn_x")
public func swiftjava_Module_fn_x(_ x: UnsafePointer<Int>?) {
    fn(x: x?.pointee)
}
```

### Kotlin wrapper

The Kotlin call-site must pass a nullable pointer. The strategy differs by signedness:

**Signed / float** — `cValuesOf(it)` creates a single-element `CValues<TVar>` on the caller's
stack. The type is inferred from the value; no explicit `Var` name is needed:

```kotlin
fun fn(x: Long?): Unit {
  swiftjava_Module_fn_x(x?.let { cValuesOf(it) })
}
```

**Unsigned and Boolean** — `cValuesOf` does not have overloads for unsigned types or `Boolean`.
Instead, a single-element array is created and its address is taken via `refTo(0)`:

```kotlin
fun acceptOptByte(b: UByte?): Unit {
  swiftjava_Module_acceptOptByte_b(b?.let { ubyteArrayOf(it).refTo(0) })
}

fun acceptOptBool(flag: Boolean?): Unit {
  swiftjava_Module_acceptOptBool_flag(flag?.let { booleanArrayOf(it).refTo(0) })
}
```

The helper `callArgForOptional(_:value:)` in `KotlinNativeSwift2KotlinGenerator.swift` encodes
this mapping:

```swift
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
```

---

## Phase 2: Optional Returns (Numeric / Boolean / Float)

### Why CDeclLowering is not used for optional returns

`lowerResult` in `FFMSwift2JavaGenerator+FunctionLowering.swift` explicitly rejects optional
returns:

```swift
case .optional:
  throw LoweringError.unhandledType(type)
```

This is a Java/FFM limitation: Java has no nullable scalar types. Kotlin/Native does, so the
Kotlin/Native generator implements its own return strategy.

### ABI

The Swift thunk heap-allocates a value of type `T` and returns a pointer to it. A null pointer
means the Swift function returned `nil`. The caller (Kotlin) must `free` the pointer after copying
the value.

```c
// Swift: func maybeInt() -> Int?
ptrdiff_t* swiftjava_Module_maybeInt(void);
```

`CType` (via `CRepresentation.swift:34`) unwraps `UnsafeMutablePointer<T>?` to `T*` in C, so
the C header declaration is identical to any other nullable pointer.

### Swift thunk

`optionalReturningThunk` in `KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` generates
the heap-allocation pattern. The type name is derived directly from the nominal type declaration
(`nom.nominalTypeDecl.name`) — no hardcoded mapping table is needed:

```swift
@_cdecl("swiftjava_Module_maybeInt")
public func swiftjava_Module_maybeInt() -> UnsafeMutablePointer<Int>? {
    guard let _result: Int = maybeInt() else { return nil }
    let _ptr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    _ptr.initialize(to: _result)
    return _ptr
}
```

### CDeclLowering signature stripping

Because `lowerFunctionSignature` throws on optional return types, `resolve()` and
`writeSwiftThunkSources` both detect an optional return and lower a _stripped_ signature (with the
wrapped, non-optional type as the return) before building the custom `CFunction` manually:

```swift
// In resolve() and writeSwiftThunkSources():
if let wrapped = optionalReturnWrapped, case .optional = ktReturn {
  strippedResult = SwiftResult(convention: ..., type: wrapped)  // e.g. Int, not Int?
}
let sigForLowering = SwiftFunctionSignature(... result: strippedResult ...)
let lowered = try CdeclLowering(...).lowerFunctionSignature(sigForLowering)
// Then build custom CFunction with UnsafeMutablePointer<T>? return type.
```

### Kotlin wrapper

```kotlin
fun maybeInt(): Long? {
  val ptr = swiftjava_Module_maybeInt() ?: return null
  val result = ptr.pointed.value
  free(ptr)
  return result
}
```

`ptr.pointed.value` dereferences the heap pointer to obtain the scalar value. `return null` and
`return result` are non-local returns, valid here because any enclosing `usePinned` or `memScoped`
lambdas are `inline`.

---

## String Optionals

### Why String needs separate handling

`String` is not a C-compatible type. The existing non-optional `String` ABI passes strings as
heap-allocated null-terminated C strings (`char*`):

- **Parameter**: `UnsafePointer<Int8>` in the thunk; Kotlin passes `.cstr`.
- **Return**: `UnsafeMutablePointer<Int8>` / `UnsafeMutablePointer<CChar>` in the thunk; the
  caller owns the allocation and must `free` it.

`lowerOptionalParameter` in `FFMSwift2JavaGenerator+FunctionLowering.swift` explicitly throws for
`String?`:

```swift
case .void, .string:
  throw LoweringError.unhandledType(knownTypes.optionalSugar(wrappedType))
```

And the general optional parameter path would produce `UnsafeRawPointer?` for non-C types (not
`UnsafePointer<Int8>?`). Both make the standard lowering path unusable for `String?`.

### Signature stripping for String? parameters

Like optional returns, `String?` parameters are _stripped_ (replaced with non-optional `String`)
before `CDeclLowering` is called. This makes the lowering succeed and produces
`UnsafePointer<Int8>` (non-optional) in the lowered signature:

```swift
let strippedParameters = decl.functionSignature.parameters.map { p -> SwiftParameter in
  guard swiftTypeToKotlin(p.type) == .optional(.string) else { return p }
  return SwiftParameter(convention: p.convention, argumentLabel: p.argumentLabel,
                        parameterName: p.parameterName, type: knownTypes.string)
}
```

The C header then shows `const int8_t*` — which Kotlin/Native cinterop treats as a nullable
`CValuesRef<ByteVar>?`, allowing null to be passed.

### `String?` as a parameter — Kotlin wrapper

The call-site uses Kotlin's safe-call operator on `.cstr`. When `s` is `null`, `s?.cstr` evaluates
to `null`, which the cinterop layer maps to a null pointer:

```kotlin
fun acceptOptString(s: String?): Unit {
  swiftjava_Module_acceptOptString_s(s?.cstr)
}
```

### `String?` as a parameter — Swift thunk

`stringOptionalAwareThunk` generates the thunk. The parameter is declared as
`UnsafePointer<Int8>?` (optional pointer) and converted via `.map { String(cString: $0) }`:

```swift
@_cdecl("swiftjava_Module_acceptOptString_s")
public func swiftjava_Module_acceptOptString_s(_ s: UnsafePointer<Int8>?) {
    acceptOptString(s: s.map { String(cString: $0) })
}
```

### `String?` as a return type — ABI

The ABI mirrors non-optional `String`: the thunk returns a heap-allocated null-terminated C string
(`char*`), with `null` meaning the Swift function returned `nil`. The C declaration is:

```c
int8_t* swiftjava_Module_maybeName(void);
```

For `String?` returns, the stripped signature (with `String` as the return type) already produces
the right `int8_t*` C type via CDeclLowering, so no custom `CFunction` construction is needed —
the `lowered.cdeclSignature` is used directly (same as the `default` branch).

### `String?` as a return type — Swift thunk

`stringOptionalAwareThunk` uses `_swiftjava_stringToCString` (from `SwiftRuntimeFunctions`) for
the heap allocation, avoiding a duplicated allocation loop:

```swift
@_cdecl("swiftjava_Module_maybeName")
public func swiftjava_Module_maybeName() -> UnsafeMutablePointer<CChar>? {
    guard let _result: String = maybeName() else { return nil }
    return _swiftjava_stringToCString(_result)
}
```

### `String?` as a return type — Kotlin wrapper

```kotlin
fun maybeName(): String? {
  val ptr = swiftjava_Module_maybeName() ?: return null
  val result = ptr.toKString()
  free(ptr)
  return result
}
```

This is identical to a non-optional `String` return except `?: return null` replaces `?: return ""`.

### Combined: `String?` param + `String?` return

`stringOptionalAwareThunk` handles this combination in a single pass:

```swift
@_cdecl("swiftjava_Module_maybeUpper_s")
public func swiftjava_Module_maybeUpper_s(_ s: UnsafePointer<Int8>?) -> UnsafeMutablePointer<CChar>? {
    guard let _result: String = maybeUpper(s: s.map { String(cString: $0) }) else { return nil }
    return _swiftjava_stringToCString(_result)
}
```

```kotlin
fun maybeUpper(s: String?): String? {
  val ptr = swiftjava_Module_maybeUpper_s(s?.cstr) ?: return null
  val result = ptr.toKString()
  free(ptr)
  return result
}
```

---

## `stringOptionalAwareThunk` — Design

`stringOptionalAwareThunk` in `KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` is
dispatched whenever _any_ of the following is true:

- `ktReturn == .optional(.string)` — String? return.
- Any parameter's Kotlin type is `.optional(.string)` — at least one String? param.

It builds the thunk from scratch without relying on `cdeclThunk` or `optionalReturningThunk`,
covering all combinations:

| Return type | Body |
|-------------|------|
| `String?` | `guard let _result: String = fn(...) else { return nil }` / `return _swiftjava_stringToCString(_result)` |
| `String` (non-optional) | `return _swiftjava_stringToCString(fn(...))` |
| Primitive optional `T?` | `guard let _result: T = fn(...) else { return nil }` / allocate pattern |
| Void | `fn(...)` |
| Any other primitive | `return fn(...)` |

String? parameters always become `_ name: UnsafePointer<Int8>?` with
`name.map { String(cString: $0) }` as the call-site conversion.

---

## Dispatch in `writeSwiftThunkSources`

The thunk generator selection follows this priority order:

```
1. ktReturn == .array(.uByte) && !isThrowing
   → arrayReturningThunk

2. (ktReturn == .optional(.string) || hasStringOptParams) && !isThrowing
   → stringOptionalAwareThunk

3. wrappedOptionalReturn != nil && !isThrowing
   → optionalReturningThunk   (numeric / bool / float optional returns)

4. default
   → lowered.cdeclThunk       (non-optional primitives, String, void)
```

Throwing functions fall through to `cdeclThunk`, which wraps the call in `do { ... } catch` and
returns `nil` on error. Custom thunks (`arrayReturningThunk`, `optionalReturningThunk`,
`stringOptionalAwareThunk`) only apply to non-throwing functions because the optional-return
sentinel (`null` pointer) would be ambiguous with a throw.

---

## Files Changed

| File | Purpose |
|------|---------|
| `Sources/JExtractSwiftLib/KotlinNative/KotlinType.swift` | Added `case optional(KotlinType)` (indirect); `description` returns `"T?"` |
| `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift` | `swiftTypeToKotlin()` — optional mapping; `resolve()` — param call-arg generation, signature stripping, `CFunction` switch; `printKotlinFunction()` — `.optional(.string)` and `.optional` cases; `callArgForOptional()` helper; conditional `free` import |
| `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` | `writeSwiftThunkSources()` — dispatch logic and signature stripping; `stringOptionalAwareThunk()`; `optionalReturningThunk()`; `extractOptionalWrappedType()` helper |
| `Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib/SimpleSwiftLib.swift` | Added optional-parameter and optional-return functions for integration testing |
| `Samples/KotlinNativeSampleApp/src/macosArm64Test/kotlin/SimpleSwiftLibTest.kt` | Integration tests for all optional-typed functions |

---

## Tests

Tests live in
`Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift`.

### Optional parameter tests

| Test | Input |
|------|-------|
| `optional_intParam` | `func acceptOpt(x: Int?)` |
| `optional_intParam_swiftThunk` | same — checks Swift thunk |
| `optional_uByteParam` | `func acceptOptByte(b: UInt8?)` |
| `optional_boolParam` | `func acceptOptBool(flag: Bool?)` |
| `optional_intParam_withPrimitiveReturn` | `func withOpt(x: Int?, y: Int) -> Int` |
| `optional_multipleOptionalParams` | `func maybeAdd(a: Int?, b: Int32?) -> Int` |
| `optional_stringParam` | `func acceptOptString(s: String?)` |
| `optional_stringParam_swiftThunk` | same — checks Swift thunk |
| `optional_stringParam_withStringReturn` | `func greetOpt(name: String?) -> String` |
| `optional_stringParam_withStringReturn_swiftThunk` | same — checks Swift thunk |

### Optional return tests

| Test | Input |
|------|-------|
| `optional_intReturn` | `func maybeInt() -> Int?` |
| `optional_intReturn_importsFree` | same — verifies `import platform.posix.free` |
| `optional_intReturn_swiftThunk` | same — checks Swift thunk |
| `optional_doubleReturn` | `func maybeDouble() -> Double?` |
| `optional_int32Return` | `func maybeInt32() -> Int32?` |
| `optional_stringReturn` | `func maybeName() -> String?` |
| `optional_stringReturn_swiftThunk` | same — checks Swift thunk |
| `optional_stringReturn_importsFree` | same — verifies `import platform.posix.free` |

### Combined optional param + return

| Test | Input |
|------|-------|
| `optional_paramAndReturn` | `func doubleOpt(x: Int?) -> Int?` |
| `optional_stringParamAndReturn` | `func maybeUpper(s: String?) -> String?` |
| `optional_stringParamAndReturn_swiftThunk` | same — checks Swift thunk |
