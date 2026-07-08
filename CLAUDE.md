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
- **Kotlin/Native** (`kotlinNative`) - NEW: Generates Kotlin/Native source that calls the Swift `@_cdecl` C thunks **directly via cinterop, with no JVM / Java FFM layer**. The most actively developed mode — supports primitives, String, and custom class/struct types.

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

# Generate Kotlin/Native bindings (direct cinterop to Swift @_cdecl thunks, no JVM)
swift run swift-java jextract \
  --swift-module MyModule \
  --input-swift path/to/swift/sources \
  --output-swift path/to/generated/swift \
  --output-java path/to/generated/kotlin \
  --java-package com.example.mymodule \
  --mode kotlinNative
# In kotlinNative mode --output-java holds the .kt wrapper + Swift thunks,
# and --output-swift holds the plain-C header consumed by the cinterop .def file.
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
Java (FFM)   Java (JNI)   Kotlin → Java FFM  Kotlin/Native + C header + Swift @_cdecl thunks
```

**Kotlin/Native backend (`KotlinNativeSwift2KotlinGenerator`)** emits **three** artifacts from a
single resolved model, all of which must agree on the C ABI:
1. **Kotlin wrapper** — `<Module>.kt`: the functions the app calls; wildcard-imports the cinterop package.
2. **C header** — `<Module>.h`: plain-C declarations consumed by the cinterop `.def` (written to `--output-swift`). A clean header is emitted rather than the SwiftPM `<Module>-Swift.h` (whose `external_source_symbol` pragmas make cinterop skip the thunks).
3. **Swift thunks** — `<Module>Module+SwiftJava.swift`: `@_cdecl` functions compiled into the Swift dynamic library.

The C ABI for thunks is lowered via the **shared FFM `CType`/`CFunction` machinery** (same source
of truth as FFM's Java `FunctionDescriptor`), except for custom class/struct returns, which use a
box-allocating thunk returning an opaque `void*` (see `.claude/ClassImpl.md`).

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
│       ├── KotlinNativeSwift2KotlinGenerator.swift             # resolve()/wrapper + C header emission
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
└── KotlinNativeSampleApp/        # Kotlin/Native direct-cinterop sample (macOS arm64, NEW)
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
layer**: generated Kotlin/Native wrappers call the Swift `@_cdecl` C thunks directly through cinterop.

**Current Status:**
- Top-level functions over a broad type set: all signed/unsigned integer widths, `Bool`, `Float`,
  `Double`, and `String` (params **and** returns).
- **Custom classes & structs** (`KotlinNative/KotlinNativeSwift2KotlinGenerator+Classes.swift`):
  each Swift nominal type becomes a Kotlin wrapper class holding an opaque `COpaquePointer` to a
  Swift-allocated box (Option B / Swift-malloc delegation — see `.claude/ClassImpl.md`). Supports
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
- Tests: `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift` (48) and
  `KotlinNativeClassTests.swift` (class/struct support, 31). Total KN suite: 79 tests.
- Sample project: `Samples/KotlinNativeSampleApp` (macOS arm64 / `macosArm64`), depends on
  `SwiftKitKN` for `SwiftHandle`; `ci-validate.sh` and `macosArm64Test` integration tests
  (including a `Counter` class exercised end-to-end through cinterop).

**Detailed design docs (in `.claude/`):**
- `ClassImpl.md` — class/struct bridging across FFM/JNI/KN, the allocation tradeoff (host-allocates
  vs Swift-malloc delegation), ARC accounting, and the KN box/destroy design implemented here.
- `ClassImplDone.md` — full implementation notes for KN class/struct support.

**Known Limitations:**
- Classes & structs are supported; enums, protocols, and generics are not. No collections or optionals.
- Members are limited to primitive/`String`/custom-type parameters and returns (no subscripts; no
  throwing members that return a custom type). Failable inits are skipped.
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
   - For `kotlinNative`, remember the three artifacts must stay in sync: the `.kt` wrapper
     (`writeExportedKotlinSources`/`printKotlinFunction`), the C header (`resolve()`/`writeCinteropHeader`),
     and the Swift `@_cdecl` thunks (`writeSwiftThunkSources` in the `+SwiftThunkPrinting.swift` file).
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
wrapper and the Swift `@_cdecl` thunks, while `--output-swift` receives the plain-C cinterop header
(the `.def` file's `headers =` target).

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
- `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift` - Kotlin/Native wrapper + C header
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
- `Samples/KotlinNativeSampleApp/` - Kotlin/Native direct-cinterop integration test (macOS arm64)

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
