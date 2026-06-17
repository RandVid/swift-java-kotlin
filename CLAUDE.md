# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**swift-java** is a comprehensive interoperability framework enabling seamless communication between Swift and Java/Kotlin. The project provides:

- **SwiftJava library** - Swift macros for calling Java libraries (Swift → Java)
- **jextract tool** - Generates Java/Kotlin bindings to Swift libraries (Java/Kotlin → Swift)
- **swift-java CLI** - Orchestrates code generation and configuration

### Generation Modes

The jextract tool supports three generation modes:
- **FFM (Foreign Function & Memory)** - Modern JDK 25+ approach with high performance (default)
- **JNI (Java Native Interface)** - Legacy compatibility for older JDKs and Android
- **Kotlin** - NEW: Generates Kotlin stub files (currently primitive types only)

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

# Generate Kotlin stubs from Swift (NEW)
swift run swift-java jextract \
  --swift-module MyModule \
  --input-swift path/to/swift/sources \
  --output-swift path/to/generated/swift \
  --output-java path/to/generated/kotlin \
  --java-package com.example.mymodule \
  --mode kotlin
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
┌──────────────┬───────────────┬─────────────────┐
│              │               │                 │
FFMGenerator   JNIGenerator   KotlinGenerator
│              │               │
Java (FFM)     Java (JNI)     Kotlin (stubs)
```

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
│   └── Kotlin/             # Kotlin code generator (1 file, NEW)
├── SwiftJavaTool/          # CLI implementation
│   ├── Commands/           # JExtractCommand, WrapJavaCommand, etc.
│   └── SwiftJava.swift     # Entry point (@main)
├── SwiftJavaConfigurationShared/  # Configuration model
│   └── JExtract/JExtractGenerationMode.swift  # ffm/jni/kotlin modes
└── JavaStdlib/             # Pre-generated Swift wrappers for java.util, java.io, etc.

Tests/JExtractSwiftTests/
└── Kotlin/KotlinTopLevelFunctionsTests.swift  # 43 Kotlin generation tests

BuildLogic/                 # Gradle plugin infrastructure
SwiftKitCore/              # Core Java runtime libraries
SwiftKitFFM/               # FFM-specific Java runtime support
Samples/                   # Example applications (integration tests)
├── SwiftJavaExtractFFMSampleApp/  # Java FFM sample
└── KotlinFFMSampleApp/           # Kotlin FFM delegation sample (NEW)
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

**Kotlin Type Mapping (current implementation):**
- `Int` (Swift 64-bit) → `Long` (Kotlin 64-bit)
- `Int32` (Swift 32-bit) → `Int` (Kotlin 32-bit)
- `Bool` → `Boolean`
- `Double` → `Double`
- `String` → `String` (parameters only, returns not supported)
- `Void`/`()` → `Unit`

### Build System Integration

**Gradle + Swift Package Manager Hybrid:**
- Swift Package Manager (`Package.swift`) - Swift components
- Gradle (`build.gradle.kts`, `settings.gradle.kts`) - Java/Kotlin components
- Custom Gradle plugins in `BuildLogic/` for jextract task registration
- Samples conditionally included with `-PskipSamples=true` flag

## Recent Developments

### Kotlin Code Generation (Added in commits bac1d07, 07a886a)

**Current Status:**
- **Delegation Mode Implemented**: Kotlin functions delegate to Java FFM classes
- Supports top-level functions with primitive types only
- Reuses existing `AnalysisResult` IR from FFM/JNI pipeline
- 43 comprehensive test cases in `Tests/JExtractSwiftTests/Kotlin/`
- Sample project: `Samples/KotlinFFMSampleApp` with integration tests

**Implementation Details:**
- Generated Kotlin code delegates to Java FFM classes (e.g., `SwiftModule.functionName(args)`)
- Type mapping at signature level: Swift Int→Kotlin Long, Swift Int32→Kotlin Int
- String parameters supported, String return types skipped (FFM limitation)
- Automatic code generation via Gradle task with DYLD_LIBRARY_PATH configuration

**Known Limitations (see DESIGN.md for details):**
- No collections, optionals, structs, classes, enums, protocols, generics
- No function overload disambiguation yet
- String return types not supported (FFM generator limitation at FunctionLowering.swift:733-735)
- Async functions skipped entirely
- Throws annotation not implemented

**Next Steps (per DESIGN.md priority order):**
1. Optional type support
2. Simple collection support
3. Struct/class generation
4. Function overload disambiguation

## Key Configuration Files

- `Sources/SwiftJavaConfigurationShared/Configuration.swift` - Central configuration model
- `Package.swift` - Swift package definition with JAVA_HOME detection
- `BuildLogic/src/main/kotlin/utilities/registerJextractTask.kt` - Gradle integration

## Common Development Patterns

### Adding a New Generator Feature

1. Modify `AnalysisResult.swift` if new IR representation needed
2. Update `Swift2JavaTranslator.swift` for Swift AST analysis
3. Implement in specific generator (`FFMSwift2JavaGenerator.swift`, `JNISwift2JavaGenerator.swift`, `KotlinSwift2KotlinGenerator.swift`)
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
The Kotlin mode currently reuses these flags rather than having separate `--kotlin-output` and `--kotlin-package` options.

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
- [Sources/JExtractSwiftLib/Kotlin/KotlinSwift2KotlinGenerator.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/Kotlin/KotlinSwift2KotlinGenerator.swift?type=file&root=%252F)

**Type system:**
- [Sources/JExtractSwiftLib/AnalysisResult.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/AnalysisResult.swift?type=file&root=%252F)
- [Sources/JExtractSwiftLib/Swift2JavaTranslator.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/JExtractSwiftLib/Swift2JavaTranslator.swift?type=file&root=%252F)

**Configuration:**
- [Sources/SwiftJavaConfigurationShared/Configuration.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/SwiftJavaConfigurationShared/Configuration.swift?type=file&root=%252F)
- [Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift?type=file&root=%252F)

**Key tests:**
- [Tests/JExtractSwiftTests/Kotlin/KotlinTopLevelFunctionsTests.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Tests/JExtractSwiftTests/Kotlin/KotlinTopLevelFunctionsTests.swift?type=file&root=%252F)

**Sample projects:**
- [Samples/KotlinFFMSampleApp/](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Samples/KotlinFFMSampleApp?type=file&root=%252F) - Kotlin FFM delegation integration test

## Additional Resources

- **DESIGN.md** - Detailed design notes for Kotlin code generation, trade-offs, and future roadmap
- **README.md** - User-facing documentation, setup instructions, WWDC25 presentation link
- **Samples/** - Example projects demonstrating various interop patterns
- **Sources/SwiftJavaDocumentation/Documentation.docc** - DoCC documentation (preview with `xcrun docc preview`)
