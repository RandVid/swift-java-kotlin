# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**swift-java** is a comprehensive interoperability framework enabling seamless communication between Swift and Java/Kotlin. The project provides:

- **SwiftJava library** - Swift macros for calling Java libraries (Swift → Java)
- **jextract tool** - Generates Java/Kotlin bindings to Swift libraries (Java/Kotlin → Swift)
- **swift-java CLI** - Orchestrates code generation and configuration

### Generation Modes

The jextract tool supports four generation modes (see `JExtractGenerationMode.swift`):
- **FFM (Foreign Function & Memory)** - Modern JDK 25+ approach with high performance (default)
- **JNI (Java Native Interface)** - Legacy compatibility for older JDKs and Android
- **Kotlin** (`kotlin`) - Generates Kotlin source that **delegates to the generated Java FFM bindings** (JVM target). Primitive types only.
- **Kotlin/Native** (`kotlinNative`) - NEW: Generates Kotlin/Native source that calls the Swift `@_cdecl` C thunks **directly via `@ImportedBridge` externals (no cinterop klib), with no JVM / Java FFM layer**. The most actively developed mode — supports primitives, String, and custom class/struct types. **Requires Kotlin 2.4.20-Beta1+** (`@ImportedBridge` / `NativePtr` are `kotlin.native.internal` APIs introduced then).

## Prerequisites

### Environment Setup

**Swift**: Version 6.2.x+ required
```bash
# Using swiftly (recommended)
swiftly install 6.2 --use
```

**Java**: JDK 25+ required for building (even though libraries support lower targets)
```bash
# Using sdkman
sdk install java 25.0.1-amzn
sdk use java 25.0.1-amzn
export JAVA_HOME="$(sdk home java current)"
```

**Kotlin**: 2.4.20-Beta1+ (centralized in `settings.gradle.kts` `pluginManagement`). Required by the
`kotlinNative` mode, whose `@ImportedBridge` transport uses `kotlin.native.internal` APIs introduced
in that release. The bump applies to every Kotlin module (all samples + `SwiftKitKN`).

**Critical**: Always set `JAVA_HOME` environment variable. Alternative: create `~/.java_home` file containing the path.

## Essential Build Commands

### Building the Project

```bash
# Build Swift components
swift build --disable-experimental-prebuilts

# Build Java components and publish to local Maven
./gradlew publishToMavenLocal

# Build without samples (faster)
./gradlew build -PskipSamples=true
```

### Running Tests

```bash
# Run Swift tests (includes code generation tests)
swift test

# Run specific Swift test
swift test --filter <type-or-method-name>

# Run Gradle/Java tests
./gradlew test

# Run sample app tests (integration tests)
cd Samples/SwiftJavaExtractFFMSampleApp
./ci-validate.sh  # builds Swift, runs Java tests
```

### Code Generation Examples

```bash
# Generate Java FFM bindings from Swift
swift run swift-java jextract \
  --swift-module MyModule \
  --input-swift path/to/swift/sources \
  --output-swift path/to/generated/swift \
  --output-java path/to/generated/java \
  --java-package com.example.mymodule \
  --mode ffm

# Generate Kotlin (JVM) stubs that delegate to Java FFM bindings
swift run swift-java jextract \
  --swift-module MyModule \
  --input-swift path/to/swift/sources \
  --output-swift path/to/generated/swift \
  --output-java path/to/generated/kotlin \
  --java-package com.example.mymodule \
  --mode kotlin

# Generate Kotlin/Native bindings (direct @ImportedBridge calls to Swift @_cdecl thunks, no JVM)
swift run swift-java jextract \
  --swift-module MyModule \
  --input-swift path/to/swift/sources \
  --output-swift path/to/generated/swift \
  --output-java path/to/generated/kotlin \
  --java-package com.example.mymodule \
  --mode kotlinNative
# In kotlinNative mode --output-java holds the .kt wrapper (incl. the @ImportedBridge
# extern declarations) + the Swift thunks. --output-swift is currently unused (no
# cinterop C header is emitted); the flag is still accepted for compatibility.
```

### Benchmarks

```bash
# Swift benchmarks
cd Benchmarks
swift package benchmark

# Java JMH benchmarks
cd Samples/SwiftJavaExtractFFMSampleApp
./gradlew jmh
```

## Architecture Overview

### Code Generation Pipeline

```
Swift Source Code
     ↓
Swift2JavaTranslator (analyzes Swift AST via SwiftSyntax)
     ↓
AnalysisResult (intermediate representation - shared by all backends)
     ↓
┌────────────┬────────────┬─────────────────┬──────────────────────┐
│            │            │                 │                      │
FFMGenerator JNIGenerator KotlinGenerator   KotlinNativeGenerator
│            │            │                 │
Java (FFM)   Java (JNI)   Kotlin → Java FFM  Kotlin/Native (@ImportedBridge) + Swift @_cdecl thunks
```

**Kotlin/Native backend (`KotlinNativeSwift2KotlinGenerator`)** emits **two** artifacts from a
single resolved model, which must agree on the C ABI:
1. **Kotlin wrapper** — `<Module>.kt`: the functions the app calls, PLUS a block of
   `@ImportedBridge("<symbol>") external fun <symbol>(…): …` declarations that bind each Swift
   `@_cdecl` thunk symbol directly (no cinterop `.def`/klib). Emitted by `printImportedBridgeExterns`.
2. **Swift thunks** — `<Module>Module+SwiftJava.swift`: `@_cdecl` functions compiled into the Swift
   dynamic library; the final Kotlin/Native binary link resolves the extern symbols against it.

There is **no C header / cinterop step** anymore. The extern signatures are still derived from the
**shared FFM `CType`/`CFunction` machinery** (same source of truth as FFM's Java `FunctionDescriptor`):
every C pointer (object/String box, `inout` cell, out-param) maps to `kotlin.native.internal.NativePtr`,
primitives map 1:1 (`kotlinExternType`). Custom class/struct returns use a box-allocating thunk
returning an opaque `void*` (see `.claude/ClassImpl.md`). Strings cross as ObjC `NSString` boxes
(`objcPtr()`/`interpretObjCPointer<String>` on the Kotlin side; `Unmanaged<NSString>` in the thunk),
not C strings.

**Opt-in:** `@ImportedBridge` / `NativePtr` live in `kotlin.native.internal`, whose marker
`InternalForKotlinNative` is itself `internal` and therefore **cannot** be named in a source
`@OptIn(...)`. The consuming Kotlin/Native module must pass the compiler flag
`-opt-in=kotlin.native.internal.InternalForKotlinNative` (plus `kotlinx.cinterop.ExperimentalForeignApi`
for the marshalling helpers). The sample sets both via `compilerOptions.optIn`.

### Key Source Structure

```
Sources/
├── SwiftJava/              # Swift→Java macros and runtime
├── JExtractSwiftLib/       # Code generation engine
│   ├── Swift2Java.swift    # Main orchestrator
│   ├── Swift2JavaTranslator.swift  # Swift AST analysis
│   ├── AnalysisResult.swift        # Intermediate representation
│   ├── SwiftTypes/         # Swift type system and symbol tables
│   ├── JavaTypes/          # Java type definitions
│   ├── FFM/                # FFM code generator (~7 files)
│   ├── JNI/                # JNI code generator (~8 files)
│   ├── Kotlin/             # Kotlin-JVM generator: KotlinSwift2KotlinGenerator.swift + KotlinType.swift
│   └── KotlinNative/       # Kotlin/Native generator (4 files, ACTIVE)
│       ├── KotlinNativeSwift2KotlinGenerator.swift             # resolve()/wrapper + @ImportedBridge externs
│       ├── KotlinNativeSwift2KotlinGenerator+Classes.swift    # class/struct wrapper emission
│       ├── KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift  # @_cdecl thunks + dispatch
│       └── KotlinType.swift                                    # KotlinType enum (primitives, object)
├── SwiftJavaTool/          # CLI implementation
│   ├── Commands/           # JExtractCommand, WrapJavaCommand, etc.
│   └── SwiftJava.swift     # Entry point (@main)
├── SwiftJavaConfigurationShared/  # Configuration model
│   └── JExtract/JExtractGenerationMode.swift  # ffm/jni/kotlin/kotlinNative modes
└── JavaStdlib/             # Pre-generated Swift wrappers for java.util, java.io, etc.

Tests/JExtractSwiftTests/
├── Kotlin/KotlinTopLevelFunctionsTests.swift              # 43 Kotlin-JVM generation tests
└── KotlinNative/                                          # Kotlin/Native generation tests
    ├── KotlinNativeTopLevelFunctionsTests.swift           # 48 top-level function tests
    └── KotlinNativeClassTests.swift                       # 31 class/struct tests

BuildLogic/                 # Gradle plugin infrastructure
SwiftKitCore/              # Core Java runtime libraries
SwiftKitFFM/               # FFM-specific Java runtime support
SwiftKitKN/                # Kotlin/Native runtime library (macOS arm64); exports SwiftHandle
Samples/                   # Example applications (integration tests)
├── SwiftJavaExtractFFMSampleApp/  # Java FFM sample
├── KotlinFFMSampleApp/           # Kotlin (JVM) FFM delegation sample
└── KotlinNativeSampleApp/        # Kotlin/Native @ImportedBridge sample (macOS arm64, NEW)
```

### Type System Architecture

**Swift Type Analysis:**
- `SwiftType` - Base type representation
- `SwiftNominalTypeDeclaration` - Classes, structs, enums
- `SwiftSymbolTable` - Module-level symbol tracking
- `SwiftKnownTypes` - Pre-defined types (Int, String, Bool, Double, etc.)

**Type Mapping Strategy:**
1. Check `SwiftType.asNominalTypeDeclaration?.knownTypeKind` (semantic, preferred)
2. Fallback to string-based pattern matching on type names
3. Language-specific translation (Java uses `ThunkNameRegistry` for overload mangling)

**Kotlin Type Mapping** (the `KotlinType` enum in `KotlinNative/KotlinType.swift` models these,
including `.object(String)` for custom class/struct wrappers):

| Swift | Kotlin | Notes |
|-------|--------|-------|
| `Int` / `Int64` | `Long` | Swift `Int` is 64-bit on Apple platforms |
| `Int32` | `Int` | |
| `Int16` | `Short` | |
| `Int8` | `Byte` | |
| `UInt` / `UInt64` | `ULong` | |
| `UInt32` | `UInt` | |
| `UInt16` | `UShort` | |
| `UInt8` | `UByte` | |
| `Bool` | `Boolean` | |
| `Float` | `Float` | |
| `Double` | `Double` | |
| `String` | `String` | params + returns (kotlinNative); **params only** in kotlin-JVM mode |
| custom `class`/`struct` | wrapper class `T` | kotlinNative only; opaque box handle (see below) |
| `Void` / `()` | `Unit` | |

**Mode-specific support:**
- **`kotlin` (JVM)** — primitive types + String *parameters* only; String returns skipped (FFM `FunctionLowering.swift:733-735` limitation).
- **`kotlinNative`** — the full table above. String returns work because the Kotlin/Native generator builds its own ABI rather than delegating to FFM. Custom **classes and structs** are bridged as wrapper classes over a Swift-allocated box. Async functions are skipped with a `// Skipped …` comment. Collections and optionals are not supported.

### Build System Integration

**Gradle + Swift Package Manager Hybrid:**
- Swift Package Manager (`Package.swift`) - Swift components
- Gradle (`build.gradle.kts`, `settings.gradle.kts`) - Java/Kotlin components
- Custom Gradle plugins in `BuildLogic/` for jextract task registration
- Samples conditionally included with `-PskipSamples=true` flag

## Recent Developments

### Kotlin/Native Code Generation (`kotlinNative` mode, ACTIVE area of work)

This is the most actively developed generator. Unlike `kotlin` (JVM) mode, it produces **no JVM
layer**: generated Kotlin/Native wrappers call the Swift `@_cdecl` C thunks directly through
`@ImportedBridge` externals (no cinterop klib; requires Kotlin 2.4.20-Beta1+ and the
`-opt-in=kotlin.native.internal.InternalForKotlinNative` compiler flag).

**Current Status:**
- Top-level functions over a broad type set: all signed/unsigned integer widths, `Bool`, `Float`,
  `Double`, and `String` (params **and** returns).
- **Custom classes & structs** (`KotlinNative/KotlinNativeSwift2KotlinGenerator+Classes.swift`):
  each Swift nominal type becomes a Kotlin wrapper class holding an `NSObject` box over a
  Swift-allocated object; `__ptr(): NativePtr = __obj.objcPtr()` yields the handle passed to the
  externs (Option B / Swift-malloc delegation — see `.claude/ClassImpl.md`). Supports
  constructors, instance methods, static methods, and stored-property get/set, plus custom types as
  parameters and return values. Member parameter/return types are limited to primitives, `String`,
  and other custom types.
  - Uniform box for class **and** struct: the init thunk `allocate`s + `initialize`s and returns a
    `void*`; methods/getters/setters reuse the shared `cdeclThunk` (`self` → `.pointee`); a per-type
    `_destroy` thunk does `deinitialize` + `deallocate`.
  - Lifetime: `SwiftHandle` (from `SwiftKitKN`, `org.swift.swiftkit.kn`) runs `_destroy`
    exactly once via `AutoCloseable.close()` (deterministic, `use {}`) or a GC `createCleaner`
    (auto), guarded by a CAS `AtomicInt`; calls after destroy throw via `ensureAlive()`.
    `SwiftHandle` is no longer emitted inline — generated code imports it from `SwiftKitKN`.
  - Accessor/dedup thunk symbols contain `$` (e.g. `value$get`), so the wrapper backtick-escapes
    cinterop references (`cinteropName`).
- Reuses the existing `AnalysisResult` IR (including `importedTypes` and their members) and the
  shared FFM `ThunkNameRegistry` / `CdeclLowering` so the C symbol names and ABI match across modes.
- Throwing functions: the shared `cdeclThunk` wraps the call in `do { … } catch` and returns `nil`
  on error.
- **`inout` parameters** (`+SwiftThunkPrinting.swift` inout thunks, `+Classes.swift`
  `renderInoutMethod`, `Inout.kt`): every Swift `inout T` surfaces as a Kotlin `Inout<T>` (a plain
  `org.swift.swiftkit.kn.Inout<T>` value holder — see below). The thunk reads each mutable slot out of
  a `void*` cell into a local `var`, calls the API with `&local`, then writes it back; the wrapper
  seeds the cell from `Inout.unsafeValue` and stores the result back into `unsafeValue`.
  - Primitive `inout`: the wrapper allocates a `memScoped` value cell (`LongVar`, …); the thunk uses
    `assumingMemoryBound(to: T.self).pointee`.
  - Custom-type `inout`: the wrapper seeds a box-pointer cell; the thunk raises the object,
    mutates it, and re-boxes into a **new** `AnyObject`, writing the new pointer back (`objectRaiseExpr`
    / `objectBoxExpr`). Lifetime stays on the GC/`interpretObjCPointer` model — no `createCleaner`.
- **Structs use a single value class + `Inout<Struct>` extensions** (`+Structs.swift`, `Inout.kt`,
  `SwiftCopyable.kt`): each struct emits one `class <Name> internal constructor(val obj: NSObject) :
  SwiftCopyable` carrying the read-only surface — `val` getters, non-mutating methods, static methods
  (companion), and `override fun copy()` (a per-struct `copy` thunk boxes a fresh value). Mutating
  operations are **top-level extensions on `Inout<Name>`**: a settable property becomes
  `var Inout<Name>.p`, a `mutating` method `fun Inout<Name>.m(…)`, a subscript setter
  `operator fun Inout<Name>.set(…)`. Each mutation treats `self` as an **`inout Self` box cell**:
  a shared `structMutationBlock` opens a `memScoped`, seeds a `self_slot` (`COpaquePointerVar`) from
  `unsafeValue.__ptr()`, calls the thunk (`self_slot.ptr` last), and swaps the holder with
  `unsafeValue = Name(wrapSwiftObject { self_slot.value })`. This is the **same `inoutThunk` mechanism
  as any `inout` argument** — there is no separate struct-mutation thunk. Because `self` rides the cell
  (not the return slot), a mutating method's return slot is free: **non-`Void` `mutating` methods
  (scalar *or custom-type* return) and `mutating` methods that also take `inout` params are supported.**
  A custom-type return is boxed by the thunk (`objectBoxExpr`) and re-wrapped on the Kotlin side
  (`inoutResultCapture`), the same convention used for any `inout` function returning a custom type.
  - `Inout<T>` is the uniform mutable/`inout` holder: `value` copies on read and write (via
    `SwiftCopyable.copy()`) to preserve value semantics; `unsafeValue` is the no-copy accessor used by
    the generated marshalling. For a non-copyable `T` (primitive / class wrapper) the copy is a no-op,
    so `Inout<T>` is a plain box. Constructing `Inout(point)` copies, so mutating the holder never
    touches the caller's original value.
  - A settable **custom-type field** gets two mutation extensions on `Inout<Rect>` (nested mutation):
    - a *connected* `val Inout<Rect>.topLeft: Inout<Point>` whose `onChange` re-embeds the point into
      the parent, so `rect.topLeft.x = 3` mutates `rect` and chains up (each write re-boxes O(depth);
      whole-field replace is `rect.topLeft.value = Point(…)`); and
    - a scoped `fun Inout<Rect>.mutateTopLeft(block: Inout<Point>.() -> Unit)` that reads the field into
      a fresh `Inout`, runs the block, and writes it back **once** (batched, no stale-alias hazard).
    Both are verified end-to-end in the sample (`Point`/`Rectangle`, `Inout<…>` mutation, value
    semantics, `recenter` `inout` param, connected + scoped nested mutation).
  - **KNOWN LIMITATIONS (not yet fixed):** the connected `rect.topLeft.x = …` path snapshots the field,
    so capturing it and mutating the parent elsewhere leaves it stale (aliasing; use `mutateTopLeft` to
    avoid); `consuming` is not expressible; a **non-mutating** struct method that takes an `inout` param
    is not surfaced (only `mutating` ones are); `String` returns from an `inout`/`mutating` function are
    still skipped (custom-type and scalar returns are supported).
  - Build caveat: the sample's Swift dylib is compiled from the SwiftPM build-plugin thunk output
    (`.build/plugins/outputs/…`), which is **not** reliably invalidated when the `swift-java` generator
    itself changes — a stale copy there produces an ABI skew against the freshly regenerated
    `@ImportedBridge` externs (e.g. a thunk still returning `char*` while the extern/wrapper now expect
    an `NSString`/`NativePtr`), which fails to link or crashes at runtime. After changing the generator,
    wipe `Samples/KotlinNativeSampleApp/.build` before rebuilding.
- Tests: `KotlinNativeTopLevelFunctionsTests.swift` and `KotlinNativeClassTests.swift` (incl. `inout`,
  struct mutating methods/setters). Sample `macosArm64Test` exercises all `inout` shapes end-to-end.
- Sample project: `Samples/KotlinNativeSampleApp` (macOS arm64 / `macosArm64`), depends on
  `SwiftKitKN` for `SwiftHandle`/`Inout`/`SwiftCopyable`; `ci-validate.sh` and `macosArm64Test` integration tests
  (including a `Counter` class and `Point` struct exercised end-to-end through `@ImportedBridge`).

**Detailed design docs (in `.claude/`):**
- `ClassImpl.md` — class/struct bridging across FFM/JNI/KN, the allocation tradeoff (host-allocates
  vs Swift-malloc delegation), ARC accounting, and the KN box/destroy design implemented here.
- `ClassImplDone.md` — full implementation notes for KN class/struct support.

**Known Limitations:**
- Classes & structs are supported; enums, protocols, and generics are not. No collections or optionals.
- Members are limited to primitive/`String`/custom-type parameters and returns (no subscripts; no
  throwing members that return a custom type). Failable inits are skipped.
- `inout` parameters are supported for primitives and custom types (surfaced as `Inout<T>`), on
  top-level functions and members; an `inout` function may return a scalar, `Void`, or a custom
  type. `inout String`, `String` by-value parameters alongside `inout`, and `String` returns from an
  `inout` function are skipped.
- Pointer identity is not preserved (the same Swift object returned twice yields two wrappers — FFM
  parity, not a regression).
- No function overload disambiguation yet.
- Async functions are skipped entirely.

### Kotlin (JVM) Code Generation (`kotlin` mode)

**Current Status:**
- **Delegation mode**: generated Kotlin delegates to the Java FFM classes (e.g.,
  `SwiftModule.functionName(args)`).
- Top-level functions, primitive types only; String parameters supported, String returns skipped
  (FFM limitation at `FunctionLowering.swift:733-735`).
- 43 test cases in `Tests/JExtractSwiftTests/Kotlin/`; sample: `Samples/KotlinFFMSampleApp`.
- Automatic code generation via Gradle task with `DYLD_LIBRARY_PATH` configuration.

## Key Configuration Files

- `Sources/SwiftJavaConfigurationShared/Configuration.swift` - Central configuration model
- `Package.swift` - Swift package definition with JAVA_HOME detection
- `BuildLogic/src/main/kotlin/utilities/registerJextractTask.kt` - Gradle integration

## Common Development Patterns

### Adding a New Generator Feature

1. Modify `AnalysisResult.swift` if new IR representation needed
2. Update `Swift2JavaTranslator.swift` for Swift AST analysis
3. Implement in specific generator (`FFMSwift2JavaGenerator.swift`, `JNISwift2JavaGenerator.swift`, `KotlinSwift2KotlinGenerator.swift`, or `KotlinNativeSwift2KotlinGenerator.swift`)
   - For `kotlinNative`, remember the two artifacts must stay in sync: the `.kt` wrapper +
     `@ImportedBridge` externs (`writeExportedKotlinSources`/`printKotlinFunction`/`printImportedBridgeExterns`)
     and the Swift `@_cdecl` thunks (`writeSwiftThunkSources` in the `+SwiftThunkPrinting.swift` file).
     Both derive their C ABI from the same resolved `CFunction`s (`kotlinExternType` maps them to the
     extern signatures), so the symbol names and ABI match.
4. Add tests to corresponding test file in `Tests/JExtractSwiftTests/`
5. Update sample app if integration testing required

### Type Mapping Extension

When adding support for a new type:
1. Add to `SwiftKnownTypes` if it's a well-known Swift type
2. Update `knownTypeKind` enumeration for semantic mapping
3. Implement language-specific translation in generator
4. Add test cases covering the new type

### Testing Strategy

**Unit Tests:** Swift Testing framework in `Tests/`
- Use assertion helpers like `assertOutput(matches: expectedChunks)`
- Tests use in-memory Swift source strings
- Focus on code generation correctness

**Integration Tests:** Sample applications in `Samples/`
- Full pipeline: Swift source → code generation → compilation → runtime execution
- Each sample has `ci-validate.sh` script
- Run with `./gradlew run` or `./gradlew test`

## Important Constraints

### Java/Kotlin Output Reuses `--output-java` and `--java-package`
The Kotlin modes currently reuse these flags rather than having separate `--kotlin-output` and
`--kotlin-package` options. In `kotlinNative` mode specifically, `--output-java` receives the `.kt`
wrapper (including the `@ImportedBridge` extern declarations) and the Swift `@_cdecl` thunks.
`--output-swift` is currently unused — no cinterop C header is emitted — but the flag is still
accepted for compatibility.

### Kotlin/Native Requires Kotlin 2.4.20-Beta1+ and an Internal Opt-In
The `@ImportedBridge` / `NativePtr` transport is only available from Kotlin **2.4.20-Beta1**. The
plugin version is centralized in `settings.gradle.kts` `pluginManagement` (bumping it upgrades every
Kotlin module — sibling samples must share one plugin classloader, so it is all-or-nothing; do not
pin a version in an individual sample's `build.gradle.kts`). The consuming module must also compile
with `-opt-in=kotlin.native.internal.InternalForKotlinNative` (that marker is `internal`, so a source
`@OptIn(...)` cannot express it) and `-opt-in=kotlinx.cinterop.ExperimentalForeignApi`.

### Kotlin/Native Requires the Mode in `swift-java.config`
When the SwiftPM plugin drives generation for a Kotlin/Native sample, the config **must** set
`"mode": "kotlinNative"`. Omitting it silently falls back to FFM mode, which emits thunks with an
incompatible ABI for Kotlin/Native.

### Swift 6.2+ Required for Rich Interface Files
The jextract tool depends on Swift 6.2's rich interface file generation. Older Swift versions will not work.

### JAVA_HOME Must Be Set
The build system requires `JAVA_HOME`. Alternative: create `~/.java_home` file. The `Package.swift` has fallback logic for SDKMAN and `/usr/libexec/java_home` on macOS.

### Sample Tests Are Runtime Tests
Many runtime tests for jextract are in sample apps rather than unit tests. Check `Samples/*/ci-validate.sh` scripts when modifying generators.

## File References

Use these file paths when referencing code locations:

**Core orchestration:**
- [Sources/SwiftJavaTool/SwiftJava.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/SwiftJavaTool/SwiftJava.swift?type=file&root=%252F) - CLI entry point
- [Sources/SwiftJavaTool/Commands/JExtractCommand.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/SwiftJavaTool/Commands/JExtractCommand.swift?type=file&root=%252F) - jextract command implementation
- [Sources/JExtractSwiftLib/Swift2Java.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/Swift2Java.swift?type=file&root=%252F) - Generation orchestrator

**Generators:**
- [Sources/JExtractSwiftLib/FFM/FFMSwift2JavaGenerator.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/FFM/FFMSwift2JavaGenerator.swift?type=file&root=%252F)
- [Sources/JExtractSwiftLib/JNI/JNISwift2JavaGenerator.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/JNI/JNISwift2JavaGenerator.swift?type=file&root=%252F)
- [Sources/JExtractSwiftLib/Kotlin/KotlinSwift2KotlinGenerator.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/Kotlin/KotlinSwift2KotlinGenerator.swift?type=file&root=%252F) - Kotlin (JVM) generator
- `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift` - Kotlin/Native wrapper + @ImportedBridge externs
- `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator+Classes.swift` - class/struct wrappers
- `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator+SwiftThunkPrinting.swift` - `@_cdecl` Swift thunks
- `Sources/JExtractSwiftLib/KotlinNative/KotlinType.swift` - `KotlinType` enum

**Type system:**
- [Sources/JExtractSwiftLib/AnalysisResult.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/AnalysisResult.swift?type=file&root=%252F)
- [Sources/JExtractSwiftLib/Swift2JavaTranslator.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/Swift2JavaTranslator.swift?type=file&root=%252F)

**Configuration:**
- [Sources/SwiftJavaConfigurationShared/Configuration.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/SwiftJavaConfigurationShared/Configuration.swift?type=file&root=%252F)
- [Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift?type=file&root=%252F)

**Key tests:**
- [Tests/JExtractSwiftTests/Kotlin/KotlinTopLevelFunctionsTests.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Tests/JExtractSwiftTests/Kotlin/KotlinTopLevelFunctionsTests.swift?type=file&root=%252F) - Kotlin (JVM) tests
- `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift` - Kotlin/Native top-level tests (48)
- `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeClassTests.swift` - Kotlin/Native class/struct tests (31)

**Sample projects:**
- [Samples/KotlinFFMSampleApp/](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Samples/KotlinFFMSampleApp?type=file&root=%252F) - Kotlin (JVM) FFM delegation integration test
- `Samples/KotlinNativeSampleApp/` - Kotlin/Native @ImportedBridge integration test (macOS arm64)

**Kotlin/Native runtime library:**
- `SwiftKitKN/build.gradle.kts` - KMP module declaration (macosArm64, macOS-only in settings)
- `SwiftKitKN/src/macosArm64Main/kotlin/org/swift/swiftkit/kn/SwiftHandle.kt` - public `SwiftHandle` class

## Additional Resources

- **`.claude/ClassImpl.md`** - class/struct bridging design: allocation options, ARC accounting, KN box/destroy rationale
- **`.claude/ClassImplDone.md`** - full implementation notes + high-effort code review for KN class/struct support; includes the worked three-artifact example (Kotlin wrapper, C header, Swift thunks) and `SwiftKitKN` migration
- **DESIGN.md** - Detailed design notes for Kotlin code generation, trade-offs, and future roadmap
- **README.md** - User-facing documentation, setup instructions, WWDC25 presentation link
- **Samples/** - Example projects demonstrating various interop patterns
- **Sources/SwiftJavaDocumentation/Documentation.docc** - DoCC documentation (preview with `xcrun docc preview`)
