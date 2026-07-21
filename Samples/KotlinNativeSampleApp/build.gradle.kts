plugins {
    kotlin("multiplatform")
}

group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

// Swift build outputs (the dynamic library the generated wrappers link against).
val swiftDebugDir = layout.projectDirectory.dir(".build/arm64-apple-macosx/debug")
// Keep generated Kotlin out of Gradle's `build/` dir: IntelliJ auto-excludes
// `build/` from indexing and does not reliably un-exclude generated Kotlin/Native
// source roots under it, which left the generated symbols unresolved (red) in the
// editor and killed the test run-gutter icons. `.build/` (already used for the C
// header and git-ignored) is indexed normally once registered as a source dir.
val generatedKotlinDir = layout.projectDirectory.dir(".build/kotlin-native-generated/kotlin")
// The `--output-swift` directory.
val generatedSwiftDir = layout.projectDirectory.dir(".build/kotlin-native-generated/swift")

// The root-built swift-java CLI (built by `swift build` at the repo root,
// e.g. via ci-validate.sh).
val swiftJavaTool = "${rootDir}/.build/arm64-apple-macosx/debug/swift-java"

// 0. Build the root swift-java project so the CLI tool is available.
val buildRootProject = tasks.register<Exec>("buildRootProject") {
    description = "Build the root swift-java project (produces the swift-java CLI)"
    workingDir = rootDir
    commandLine("swift", "build", "--disable-experimental-prebuilts")
    inputs.dir("${rootDir}/Sources")
    outputs.file(swiftJavaTool)
}

// 1. Build the Swift dynamic library. The JExtractSwiftPlugin emits the FFM
//    @_cdecl thunks and the SimpleSwiftLib-Swift.h header during this build.
val swiftBuild = tasks.register<Exec>("swiftBuild") {
    description = "Build the SimpleSwiftLib Swift dynamic library + jextract header"
    workingDir = projectDir
    commandLine("swift", "build", "--disable-experimental-prebuilts")
    inputs.dir("Sources/SimpleSwiftLib")
    outputs.dir(swiftDebugDir)
}

// 2. Generate the Kotlin/Native wrappers (kotlinNative mode). These call the
//    @_cdecl C thunks directly through @ImportedBridge externals (no cinterop klib).
val generateKotlinNativeBindings = tasks.register<Exec>("generateKotlinNativeBindings") {
    description = "Generate Kotlin/Native bindings using jextract --mode kotlinNative"
    workingDir = rootDir
    environment("DYLD_LIBRARY_PATH", "/usr/lib/swift")
    commandLine(
        swiftJavaTool, "jextract",
        "--swift-module", "SimpleSwiftLib",
        "--input-swift", "Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib",
        "--output-swift", "Samples/KotlinNativeSampleApp/.build/kotlin-native-generated/swift",
        "--output-java", "Samples/KotlinNativeSampleApp/.build/kotlin-native-generated/kotlin",
        "--java-package", "com.example.kotlinnative",
        "--mode", "kotlinNative"
    )
    inputs.dir("Sources/SimpleSwiftLib")
    // Re-run generation when the swift-java tool itself changes, otherwise Gradle
    // treats the task as up-to-date and reuses stale wrappers after a tool rebuild.
    inputs.file(swiftJavaTool)
    outputs.dir(generatedKotlinDir)
    outputs.dir(generatedSwiftDir)
    dependsOn(buildRootProject)
}

// The Swift @_cdecl thunk symbols are bound directly with `@ImportedBridge` in the
// generated Kotlin wrappers (no cinterop `.def`/klib). The final Kotlin/Native
// binary link resolves them against libSimpleSwiftLib, so the link flags that used
// to live in the `.def` now live on the target's binaries (see `binaries.all`).
val swiftLinkerOpts = swiftDebugDir.asFile.absolutePath.let { debug ->
    listOf("-L", debug, "-lSimpleSwiftLib", "-L", "/usr/lib/swift", "-rpath", debug, "-rpath", "/usr/lib/swift")
}

kotlin {
    macosArm64 {
        compilations.all {
            // Opt in build-wide so the generated wrappers and tests don't need
            // per-call annotations:
            //  - ExperimentalForeignApi: kotlinx.cinterop (memScoped/objcPtr/…).
            //  - InternalForKotlinNative: @ImportedBridge / NativePtr. Its marker is
            //    `internal`, so it can only be opted in via this -opt-in= flag, never
            //    a source @OptIn(...) — the generated wrappers rely on this.
            compileTaskProvider.configure {
                compilerOptions.optIn.add("kotlinx.cinterop.ExperimentalForeignApi")
                compilerOptions.optIn.add("kotlin.experimental.ExperimentalNativeApi")
                compilerOptions.optIn.add("kotlin.native.internal.InternalForKotlinNative")
            }
        }
        // Every macosArm64 binary (the demo executable AND the test executable)
        // links directly against the Swift dynamic library.
        binaries.all {
            linkerOpts(swiftLinkerOpts)
        }
        // Runnable demo. Produces runDebugExecutableMacosArm64 (aliased as `run`).
        binaries {
            executable {
                entryPoint = "com.example.kotlinnative.main"
            }
        }
    }

    sourceSets {
        val macosArm64Main by getting {
            kotlin.srcDir(generatedKotlinDir)
            dependencies {
                implementation(project(":SwiftKitKN"))
            }
        }
        val macosArm64Test by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }
    }
    sourceSets.macosArm64Test.dependencies {
        implementation(kotlin("test"))
    }
}

// Task wiring: the Kotlin compilation needs the generated wrappers, and the link
// step needs the Swift dynamic library.
tasks.matching { it.name == "compileKotlinMacosArm64" }.configureEach {
    dependsOn(generateKotlinNativeBindings)
}
tasks.matching { it.name.startsWith("link") && it.name.contains("MacosArm64") }.configureEach {
    dependsOn(swiftBuild)
}

// Convenience alias so the demo runs like the KotlinFFM sample's `run`:
//   ./gradlew :Samples:KotlinNativeSampleApp:run
tasks.register("run") {
    group = "application"
    description = "Run the Kotlin/Native demo (macosArm64)"
    dependsOn("runDebugExecutableMacosArm64")
}
