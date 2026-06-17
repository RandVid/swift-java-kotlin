# KotlinNativeSampleApp

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

If you get `Exception in thread "main" java.lang.Error: /var/folders/7k/3x4vdcjj1w537v4w0gk3qwz40000gn/T/8637267871315052262.c:1:10: fatal error: 'SimpleSwiftLib.h' file not found`,
clean both build directories and check whether you have built the main `swift-java` tool
