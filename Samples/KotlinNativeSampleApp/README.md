# KotlinNativeSampleApp

Demonstrates the `kotlinNative` jextract mode: generating **Kotlin/Native**
bindings to a Swift library that call the Swift `@_cdecl` C thunks **directly
via cinterop**, with no JVM and no Java FFM layer.

```
Kotlin/Native test  ──▶  generated Kotlin wrappers  ──▶  cinterop bindings
                                                              │
                                                              ▼
                                       Swift @_cdecl C thunks in libSimpleSwiftLib.dylib
```

Contrast with [`KotlinFFMSampleApp`](../KotlinFFMSampleApp), which targets the
JVM and delegates through generated Java FFM classes
(`Kotlin/JVM → Java FFM → Swift`).

## How it works

1. `swift build` compiles `SimpleSwiftLib` and the `JExtractSwiftPlugin` emits
   the FFM `@_cdecl` thunks (exported C symbols like
   `swiftjava_SimpleSwiftLib_add_a_b`).
2. `swift-java jextract --mode kotlinNative` generates:
   - `SimpleSwiftLib.kt` — Kotlin/Native wrappers calling the thunks, and
   - `SimpleSwiftLib.h` — a plain-C header declaring those thunks for cinterop.
3. Gradle writes a cinterop `.def` (pointing at the header + the dylib), runs
   cinterop, compiles the wrappers, and links the native test binary.

## Scope

Top-level functions over `Int`/`Int32`/`Bool`/`Double`/`Void`, plus `String`
**parameters** (marshalled as a null-terminated UTF-8 C string via `String.cstr`).
`String` **returns** and other types are still skipped (a String return hands
back a heap pointer the caller must free — see `MIGRATION.md`).

## Requirements

macOS on Apple Silicon (target `macosArm64`), Xcode Command Line Tools (for the
macOS SDK), and the Kotlin/Native (konan) toolchain (downloaded automatically by
the Kotlin Gradle plugin on first build). The module is skipped on non-macOS
hosts via `settings.gradle.kts`.

## Run

```bash
# Run the demo app (like KotlinFFMSampleApp's `run`)
./gradlew :Samples:KotlinNativeSampleApp:run

# Run the integration tests
./gradlew :Samples:KotlinNativeSampleApp:macosArm64Test

# Or the CI entry point (also builds the root swift-java tool)
cd Samples/KotlinNativeSampleApp && ./ci-validate.sh
```

`run` is an alias for the Kotlin/Native `runDebugExecutableMacosArm64` task. The
demo entry point is `com.example.kotlinnative.main` in
`src/macosArm64Main/kotlin/KotlinNativeDemo.kt`.
