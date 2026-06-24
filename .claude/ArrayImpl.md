# UByteArray Implementation in Kotlin/Native Generator

This document describes the implementation of `[UInt8]` (Swift) ↔ `UByteArray` (Kotlin) support
in `KotlinNativeSwift2KotlinGenerator` — both as a function parameter and as a return type.

## Overview

The Kotlin/Native generator (`KotlinNativeSwift2KotlinGenerator`) emits three artifacts from the
same resolved model:

1. **Kotlin wrapper** — `<Module>.kt`, functions the app calls.
2. **C header** — `<Module>.h`, plain-C declarations consumed by the cinterop `.def` file.
3. **Swift thunks** — `<Module>Module+SwiftJava.swift`, `@_cdecl` functions compiled into the
   Swift dynamic library.

All three artifacts must agree on the C ABI. `[UInt8]` required custom handling in each artifact
because the FFM and Kotlin/Native ABIs differ for array types.

---

## Why a Custom ABI for Arrays

The FFM generator uses a **callback ABI** for array returns:

```c
// FFM ABI
void thunk(..., void (*result_init)(const void*, ptrdiff_t));
```

Swift calls back into Java with a temporary pointer via the function pointer. This works with
`Linker.upcallStub()` in Panama (Java FFM), which creates a C function pointer backed by a JVM
trampoline with embedded context.

Kotlin/Native has no equivalent. Its `staticCFunction` produces a compile-time static symbol with
**no closure context** — it cannot capture local variables. Passing a `staticCFunction` that writes
to a stack variable would be undefined behaviour.

Instead, Kotlin/Native uses the **heap-pointer + out-count ABI**:

```c
// KN ABI
uint8_t* thunk(..., ptrdiff_t* result_count);  // caller must free()
```

Swift heap-allocates the array, writes the count through the pointer, and returns the base address.
The caller frees it after copying.

---

## `[UInt8]` as a Parameter

### Type mapping

`swiftTypeToKotlin` maps `[UInt8]` (Swift) → `.array(.uByte)` (Kotlin):

```swift
// KotlinNativeSwift2KotlinGenerator.swift
case .array(let element):
    if let inner = swiftTypeToKotlin(element), inner == .uByte {
        return .array(.uByte)
    }
```

The string-fallback path also handles `"[UInt8]"` and `"[Swift.UInt8]"` directly.

### C ABI lowering

`[UInt8]` parameters are lowered to a `(const void*, ptrdiff_t)` pair by the shared
`CdeclLowering` machinery — the same lowering FFM uses. The C header declaration looks like:

```c
uint8_t swiftjava_Module_process_data(const void* data_pointer, ptrdiff_t data_count);
```

### Kotlin wrapper — `usePinned`

Kotlin/Native's GC can move heap objects. Before passing a `UByteArray`'s address to C, the array
must be **pinned** (address-stabilised). `usePinned` is a Kotlin/Native `inline` function that pins
for the duration of its lambda:

```kotlin
fun processData(data: UByteArray): UByte {
  return data.usePinned { pinned_data ->
    swiftjava_Module_process_data(pinned_data.addressOf(0), data.size.toLong())
  }
}
```

`pinned_data.addressOf(0)` passes the base address; `data.size.toLong()` passes the element count
as `ptrdiff_t`.

For **multiple** array parameters the blocks nest:

```kotlin
fun mix(a: UByteArray, b: UByteArray): UByte {
  return a.usePinned { pinned_a ->
    b.usePinned { pinned_b ->
      swiftjava_Module_mix(pinned_a.addressOf(0), a.size.toLong(),
                           pinned_b.addressOf(0), b.size.toLong())
    }
  }
}
```

Only the **outermost** `usePinned` carries a `return` prefix (for non-`Unit` returns) because
`usePinned` is `inline` — the lambda's last expression propagates out to the function.

### Swift thunk — standard `cdeclThunk`

Array parameters use the standard FFM `cdeclThunk` path (no special handling needed on the Swift
side). The lowered `@_cdecl` thunk reconstructs the `[UInt8]` from the raw pointer and count:

```swift
@_cdecl("swiftjava_Module_process_data")
public func swiftjava_Module_process_data(_ data_pointer: UnsafeRawPointer, _ data_count: Int) -> UInt8 {
  return processData(data: [UInt8](UnsafeRawBufferPointer(start: data_pointer, count: data_count)))
}
```

---

## `[UInt8]` as a Return Type

### Kotlin wrapper — `memScoped` + out-count

The KN heap-pointer ABI requires a stack-allocated variable to receive the count. `memScoped` is
a Kotlin/Native `inline` function that provides a `MemScope` for stack allocation via `alloc<T>()`.
Because it is `inline`, a non-local `return` is valid inside its lambda.

```kotlin
fun getData(): UByteArray {
  memScoped {
    val countVar = alloc<LongVar>()
    val ptr = swiftjava_Module_getData(countVar.ptr) ?: return UByteArray(0)
    val count = countVar.value.convert<Int>()
    val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()
    free(ptr)
    return result
  }
}
```

Steps:
1. `alloc<LongVar>()` — stack-allocates the out-count (`ptrdiff_t*`, mapped to `LongVar` in
   Kotlin/Native cinterop on 64-bit).
2. Thunk call — passes `countVar.ptr`; returns `null` if the array is empty → early return of
   `UByteArray(0)`.
3. `countVar.value.convert<Int>()` — reads the written count.
4. `ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()` — copies bytes into a managed
   `UByteArray`.
5. `free(ptr)` — releases the heap allocation; needs `import platform.posix.free` (not in
   `kotlinx.cinterop`).

When array **parameters** are also present, `memScoped` nests inside the innermost `usePinned`
block. In that case the last expression of `memScoped` (`result`) propagates out through each
`usePinned` lambda to the enclosing `return`:

```kotlin
fun transform(input: UByteArray): UByteArray {
  return input.usePinned { pinned_input ->
    memScoped {
      val countVar = alloc<LongVar>()
      val ptr = swiftjava_Module_transform(
          pinned_input.addressOf(0), input.size.toLong(),
          countVar.ptr) ?: return UByteArray(0)
      val count = countVar.value.convert<Int>()
      val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()
      free(ptr)
      result   // last expression; propagates through usePinned, returned by outer `return`
    }
  }
}
```

### `import platform.posix.free`

`free` is emitted conditionally — only when at least one function returns `String` or
`UByteArray`:

```swift
// KotlinNativeSwift2KotlinGenerator.swift
let needsFree = resolvedFunctions().contains {
    if case .emit(let fn) = $0 {
        return fn.kotlinReturn == .string || fn.kotlinReturn == .array(.uByte)
    }
    return false
}
if needsFree {
    printer.print("import platform.posix.free")
}
```

### C header declaration

`resolve()` builds a **custom** `CFunction` for array-returning functions instead of delegating
to `CdeclLowering.cdeclSignature` (which would produce the FFM callback ABI). It manually
constructs the KN-specific signature:

```swift
// resolve() in KotlinNativeSwift2KotlinGenerator.swift
case .array(.uByte):
    callArgs.append("countVar.ptr")
    let knownTypes = SwiftKnownTypes(symbolTable: symbolTable)
    let normalParams = lowered.parameters.flatMap { $0.cdeclParameters }
    let countParam = SwiftParameter(
        convention: .byValue,
        parameterName: "result_count",
        type: knownTypes.unsafeMutablePointer(knownTypes.int)
    )
    let customSig = SwiftFunctionSignature(
        selfParameter: nil,
        parameters: normalParams + [countParam],
        result: SwiftResult(convention: .direct,
                            type: knownTypes.unsafeMutablePointer(knownTypes.uint8)),
        ...
    )
    cFunction = try CFunction(cdeclSignature: customSig, cName: thunkName)
```

The resulting C header entry is:

```c
uint8_t *swiftjava_Module_getData(ptrdiff_t *result_count);
```

### Swift thunk — `arrayReturningThunk`

`writeSwiftThunkSources` detects `.array(.uByte)` returns and calls `arrayReturningThunk` instead
of the shared `cdeclThunk`. The generated thunk heap-allocates and copies the Swift array:

```swift
@_cdecl("swiftjava_Module_getData")
public func swiftjava_Module_getData(_ result_count: UnsafeMutablePointer<Int>)
    -> UnsafeMutablePointer<UInt8>? {
    let _result: [UInt8] = getData()
    result_count.pointee = _result.count
    guard !_result.isEmpty else { return nil }
    let _ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: _result.count)
    _result.withUnsafeBytes { _buf in
        _ptr.initialize(from: _buf.bindMemory(to: UInt8.self).baseAddress!, count: _result.count)
    }
    return _ptr
}
```

The caller (`free(ptr)` in Kotlin) releases this allocation.

---

## The SIGBUS Bug and Its Fix

### Root cause

Before the fix, the SwiftPM plugin (`JExtractSwiftPlugin`) ran `swift-java jextract` in the
default **FFM mode** (no `mode` key in `swift-java.config`). It generated an FFM-callback-ABI
thunk:

```swift
// FFM thunk (WRONG for KN)
@_cdecl("swiftjava_SimpleSwiftLib_returnArray")
public func swiftjava_SimpleSwiftLib_returnArray(
    _ _result_initialize: @convention(c) (UnsafeRawPointer, Int) -> ()) {
  ...
  _result_initialize(_0.baseAddress!, _0.count)
}
```

At runtime, Kotlin passed `countVar.ptr` (a `CPointer<LongVar>`, a stack address) as the first
argument. The FFM thunk interpreted this as a C function pointer and tried to jump to the stack
address → **SIGBUS (signal 138)**.

### Fix

Three changes were required:

**1. `swift-java.config`** — declare `kotlinNative` mode so the plugin generates the right thunks:

```json
{
  "javaPackage": "com.example.kotlinnative",
  "mode": "kotlinNative"
}
```

**2. `KotlinNativeSwift2KotlinGenerator.generate()`** — write Swift thunks and empty placeholder
files during code generation:

```swift
func generate() throws {
    var printer = CodePrinter()
    try writeExportedKotlinSources(printer: &printer)

    var headerPrinter = CodePrinter()
    try writeCinteropHeader(printer: &headerPrinter)

    try writeSwiftThunkSourcesToDisk()    // new
    try writeExpectedEmptySwiftSources()  // new
}
```

`writeSwiftThunkSourcesToDisk()` writes `<Module>Module+SwiftJava.swift` — the file the SwiftPM
plugin declares as its output — to `cinteropHeaderDirectory` (the `--output-swift` path).
`writeExpectedEmptySwiftSources()` writes empty `<SourceFile>+SwiftJava.swift` placeholders for
every input `.swift` file plus `Foundation+SwiftJava.swift`, which SwiftPM requires to exist.

**3. `writeSwiftThunkSources`** — add `import SwiftRuntimeFunctions` so that the shared
`cdeclThunk` path (used for all non-array returns) can resolve `_swiftjava_stringToCString`:

```swift
printer.print("import SwiftRuntimeFunctions")
```

---

## Files Changed

| File | Purpose |
|------|---------|
| `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift` | `resolve()` — custom `CFunction` for array returns; `printKotlinFunction()` — `usePinned` / `memScoped` emission; conditional `free` import |
| `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` | `writeSwiftThunkSourcesToDisk()`, `writeExpectedEmptySwiftSources()`, `writeSwiftThunkSources()`, `arrayReturningThunk()` |
| `Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib/swift-java.config` | Added `"mode": "kotlinNative"` |
| `Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib/SimpleSwiftLib.swift` | Added `returnArray()` and `returnFirstElement(arr:)` to the sample |

---

## Tests

Tests live in
`Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift`.

### Parameter tests

| Test | Input |
|------|-------|
| `byteArray_asParameter_unitReturn` | `func process(data: [UInt8])` |
| `byteArray_asParameter_intReturn` | `func firstByte(data: [UInt8]) -> Int` |
| `byteArray_asParameter_stringReturn` | `func decode(data: [UInt8]) -> String` |
| `byteArray_multipleArrayParameters` | `func mix(a: [UInt8], b: [UInt8]) -> UInt8` |
| `byteArray_mixedWithPrimitiveParameters` | `func process(n: Int, data: [UInt8]) -> UInt8` |

### Return type tests

| Test | Input |
|------|-------|
| `byteArray_asReturn_noParams` | `func getData() -> [UInt8]` |
| `byteArray_asReturn_withPrimitiveParams` | `func repeatByte(byte: UInt8, count: Int) -> [UInt8]` |
| `byteArray_asReturn_withArrayParam` | `func transform(input: [UInt8]) -> [UInt8]` |
| `byteArray_asReturn_freeIsImported` | verifies `import platform.posix.free` is emitted |

### Swift thunk tests

| Test | What it checks |
|------|---------------|
| `swiftThunk_byteArrayReturn` | `arrayReturningThunk` output for `getData() -> [UInt8]` |
| `swiftThunk_byteArrayParam` | standard `cdeclThunk` output for `process(data: [UInt8]) -> UInt8` |
