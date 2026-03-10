# Kotlin FFM Sample Application

This sample demonstrates **Kotlin calling Swift** via the FFM (Foreign Function & Memory) delegation approach.

## Architecture

```
Kotlin Code (SimpleSwiftLibTest.kt)
         ↓
Generated Kotlin Wrappers (SimpleSwiftLib.kt)
         ↓ (delegates to)
Generated Java FFM Classes (SimpleSwiftLib.java)
         ↓ (native calls via FFM)
Swift Native Library (SimpleSwiftLib.swift)
```

## What This Demonstrates

- **Kotlin code generation** with `--mode kotlin`
- **FFM delegation** - Kotlin functions delegate to Java FFM classes
- **Primitive type support**: `Int`, `String`, `Boolean`, `Double`, `Unit`
- **End-to-end testing** of the complete Kotlin → Java → Swift call chain

## Swift Functions

The sample includes these simple functions with primitive types:

```swift
public func helloWorld()                              // Void function
public func add(a: Int, b: Int) -> Int                // Int parameters and return
public func greet(name: String) -> String             // String parameter and return
public func isPositive(value: Int) -> Bool            // Boolean return
public func divide(a: Double, b: Double) -> Double    // Double parameters
public func printMessage(message: String)             // Void with String parameter
```

## Building and Running

### Prerequisites

- Swift 6.2+
- JDK 25+
- Gradle 8+
- Set `JAVA_HOME` environment variable

### Build

```bash
# From repository root
./gradlew :KotlinFFMSampleApp:build
```

This will:
1. Build the Swift library (`SimpleSwiftLib`)
2. Generate Java FFM bindings (via `jextract` task)
3. Generate Kotlin wrappers (via `generateKotlinBindings` task)
4. Compile all Kotlin and Java code
5. Run the tests

### Run Tests

```bash
./gradlew :KotlinFFMSampleApp:test
```

Expected output: All 8 tests pass ✅

### Run Demo Application

```bash
./gradlew :KotlinFFMSampleApp:run
```

Expected output shows successful Kotlin → Swift calls:
```
=== Kotlin FFM Delegation Demo ===

1. Calling void function:
Hello from Swift!

2. Calling function with Int parameters and return:
   add(10, 32) = 42

3. Calling function with String parameter and return:
   greet("Kotlin Developer") = "Hello, Kotlin Developer!"

...
```

## Generated Code

### Generated Kotlin (`.build/kotlin-generated/kotlin/com/example/kotlinffm/SimpleSwiftLib.kt`)

```kotlin
fun helloWorld(): Unit {
  SimpleSwiftLib.helloWorld()
}

fun add(a: Int, b: Int): Int {
  return SimpleSwiftLib.add(a, b)
}

// ... more delegating functions
```

### Generated Java FFM (`.build/plugins/outputs/.../SimpleSwiftLib.java`)

```java
public class SimpleSwiftLib {
    public static void helloWorld() {
        swiftjava_SimpleSwiftLib_helloWorld.call();
    }

    private static class swiftjava_SimpleSwiftLib_helloWorld {
        private static final FunctionDescriptor DESC = FunctionDescriptor.ofVoid();
        private static final MemorySegment ADDR =
            SimpleSwiftLib.findOrThrow("swiftjava_SimpleSwiftLib_helloWorld");
        private static final MethodHandle HANDLE =
            Linker.nativeLinker().downcallHandle(ADDR, DESC);

        public static void call() {
            try {
                HANDLE.invokeExact();
            } catch (Throwable ex$) {
                throw new AssertionError("should not reach here", ex$);
            }
        }
    }
}
```

## Key Files

- [Sources/SimpleSwiftLib/SimpleSwiftLib.swift](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Samples/KotlinFFMSampleApp/Sources/SimpleSwiftLib/SimpleSwiftLib.swift?type=file&root=%252F) - Swift source with primitive functions
- [build.gradle.kts](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Samples/KotlinFFMSampleApp/build.gradle.kts?type=file&root=%252F) - Build configuration with Kotlin generation task
- [src/test/kotlin/.../SimpleSwiftLibTest.kt](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Samples/KotlinFFMSampleApp/src/test/kotlin/com/example/kotlinffm/SimpleSwiftLibTest.kt?type=file&root=%252F) - Kotlin tests
- [src/main/kotlin/.../KotlinFFMDemo.kt](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/Samples/KotlinFFMSampleApp/src/main/kotlin/com/example/kotlinffm/KotlinFFMDemo.kt?type=file&root=%252F) - Demo application

## Current Limitations

The Kotlin generator currently supports:
- ✅ Top-level functions only
- ✅ Primitive types: `Int`, `Bool`, `Double`, `String`, `Void`/`Unit`
- ❌ Collections (`Array`, `Dictionary`, `Set`)
- ❌ Optionals (`Int?`, `String?`)
- ❌ Structs, classes, enums
- ❌ Protocols, generics
- ❌ Async functions, throwing functions

See [DESIGN.md](fleet-file://utdu5g2ng8hqlmm30vu8/Users/ilya.plisko/IdeaProjects/swift-java-kotlin/DESIGN.md?type=file&root=%252F) for future roadmap.

## Troubleshooting

**Build fails with "swift-java not found"**:
- Build the project from root first: `./gradlew build`

**Tests fail with native library errors**:
- Ensure `JAVA_HOME` is set correctly
- Check that JDK 25+ is installed

**Kotlin compilation fails**:
- Make sure `generateKotlinBindings` task runs before `compileKotlin`
- Check `.build/kotlin-generated/kotlin/` for generated files
