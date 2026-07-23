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
val generatedKotlinDir = layout.projectDirectory.dir(".build/kotlin-native-generated/kotlin")
val generatedSwiftDir = layout.projectDirectory.dir(".build/kotlin-native-generated/swift")

// The root-built swift-java CLI (built by `swift build` at the repo root).
val swiftJavaTool = "${rootDir}/.build/arm64-apple-macosx/debug/swift-java"

// 0. Build the root swift-java project so the CLI tool is available.
val buildRootProject = tasks.register<Exec>("buildRootProject") {
    description = "Build the root swift-java project (produces the swift-java CLI)"
    workingDir = rootDir
    commandLine("swift", "build", "--disable-experimental-prebuilts")
    inputs.dir("${rootDir}/Sources")
    outputs.file(swiftJavaTool)
}

// 1. Build the Swift dynamic library. The JExtractSwiftPlugin emits the
//    @_cdecl thunks during this build.
val swiftBuild = tasks.register<Exec>("swiftBuild") {
    description = "Build the StressLib Swift dynamic library + jextract thunks"
    workingDir = projectDir
    commandLine("swift", "build", "--disable-experimental-prebuilts")
    inputs.dir("Sources/StressLib")
    outputs.dir(swiftDebugDir)
}

// 2. Generate the Kotlin/Native wrappers (kotlinNative mode).
val generateKotlinNativeBindings = tasks.register<Exec>("generateKotlinNativeBindings") {
    description = "Generate Kotlin/Native bindings using jextract --mode kotlinNative"
    workingDir = rootDir
    environment("DYLD_LIBRARY_PATH", "/usr/lib/swift")
    commandLine(
        swiftJavaTool, "jextract",
        "--swift-module", "StressLib",
        "--input-swift", "Samples/KotlinNativeStructStressApp/Sources/StressLib",
        "--output-swift", "Samples/KotlinNativeStructStressApp/.build/kotlin-native-generated/swift",
        "--output-java", "Samples/KotlinNativeStructStressApp/.build/kotlin-native-generated/kotlin",
        "--java-package", "com.example.stress",
        "--mode", "kotlinNative"
    )
    inputs.dir("Sources/StressLib")
    inputs.file(swiftJavaTool)
    outputs.dir(generatedKotlinDir)
    outputs.dir(generatedSwiftDir)
    dependsOn(buildRootProject)
}

val swiftLinkerOpts = swiftDebugDir.asFile.absolutePath.let { debug ->
    listOf("-L", debug, "-lStressLib", "-L", "/usr/lib/swift", "-rpath", debug, "-rpath", "/usr/lib/swift")
}

kotlin {
    macosArm64 {
        compilations.all {
            compileTaskProvider.configure {
                compilerOptions.optIn.add("kotlinx.cinterop.ExperimentalForeignApi")
                compilerOptions.optIn.add("kotlin.experimental.ExperimentalNativeApi")
                compilerOptions.optIn.add("kotlin.native.internal.InternalForKotlinNative")
            }
        }
        binaries.all {
            linkerOpts(swiftLinkerOpts)
        }
        binaries {
            executable {
                entryPoint = "com.example.stress.main"
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
    }
}

tasks.matching { it.name == "compileKotlinMacosArm64" }.configureEach {
    dependsOn(generateKotlinNativeBindings)
}
tasks.matching { it.name.startsWith("link") && it.name.contains("MacosArm64") }.configureEach {
    dependsOn(swiftBuild)
}

tasks.register("run") {
    group = "application"
    description = "Run the Kotlin/Native stress demo (macosArm64)"
    dependsOn("runDebugExecutableMacosArm64")
}
