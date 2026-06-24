plugins {
    kotlin("multiplatform")
}

group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

// Swift build outputs (the dynamic library + the jextract-generated
// `<Module>-Swift.h` header that cinterop consumes).
val swiftDebugDir = layout.projectDirectory.dir(".build/arm64-apple-macosx/debug")
val generatedKotlinDir = layout.buildDirectory.dir("kotlin-native-generated/kotlin")
// The generator emits a plain-C header for cinterop here (via --output-swift).
val generatedHeaderDir = layout.projectDirectory.dir(".build/kotlin-native-generated/swift")
val cinteropDefFile = layout.projectDirectory.file("native/SimpleSwiftLib.def")

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
//    @_cdecl C thunks directly through the cinterop bindings.
val generateKotlinNativeBindings = tasks.register<Exec>("generateKotlinNativeBindings") {
    description = "Generate Kotlin/Native bindings using jextract --mode kotlinNative"
    workingDir = rootDir
    environment("DYLD_LIBRARY_PATH", "/usr/lib/swift")
    commandLine(
        swiftJavaTool, "jextract",
        "--swift-module", "SimpleSwiftLib",
        "--input-swift", "Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib",
        "--output-swift", "Samples/KotlinNativeSampleApp/.build/kotlin-native-generated/swift",
        "--output-java", "Samples/KotlinNativeSampleApp/build/kotlin-native-generated/kotlin",
        "--java-package", "com.example.kotlinnative",
        "--mode", "kotlinNative"
    )
    inputs.dir("Sources/SimpleSwiftLib")
    // Re-run generation when the swift-java tool itself changes, otherwise Gradle
    // treats the task as up-to-date and reuses stale wrappers after a tool rebuild.
    inputs.file(swiftJavaTool)
    outputs.dir(generatedKotlinDir)
    outputs.dir(generatedHeaderDir)
    dependsOn(buildRootProject)
}

// 3. Write the cinterop .def with absolute paths resolved by Gradle. The
//    Swift runtime dylibs (libSwiftJava, libSwiftRuntimeFunctions) live next
//    to libSimpleSwiftLib in the SPM debug dir; libswiftCore is in /usr/lib/swift.
val generateCinteropDef = tasks.register("generateCinteropDef") {
    description = "Generate the cinterop .def for SimpleSwiftLib"
    val def = cinteropDefFile.asFile
    val debug = swiftDebugDir.asFile
    val include = generatedHeaderDir.asFile
    outputs.file(def)
    dependsOn(swiftBuild, generateKotlinNativeBindings)
    doLast {
        def.parentFile.mkdirs()
        // Bind against the generator-produced plain-C header (SimpleSwiftLib.h),
        // not the SwiftPM <Module>-Swift.h: the latter marks the thunks with
        // external_source_symbol(language="Swift"), so cinterop skips them.
        def.writeText(
            """
            package = com.example.kotlinnative.cinterop
            headers = SimpleSwiftLib.h
            compilerOpts = -I${include}
            linkerOpts = -L${debug} -lSimpleSwiftLib -L/usr/lib/swift -rpath ${debug} -rpath /usr/lib/swift
            """.trimIndent() + "\n"
        )
    }
}

kotlin {
    macosArm64 {
        compilations.getByName("main") {
            cinterops {
                create("SimpleSwiftLib") {
                    definitionFile.set(cinteropDefFile)
                }
            }
        }
        compilations.all {
            // cinterop bindings are an experimental API; opt in build-wide so
            // the generated wrappers and tests don't need per-call annotations.
            compileTaskProvider.configure {
                compilerOptions.optIn.add("kotlinx.cinterop.ExperimentalForeignApi")
            }
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
        }
        val macosArm64Test by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }
    }
}

// Task wiring: the cinterop step needs the dylib + header + .def; the Kotlin
// compilation needs the generated wrappers.
tasks.matching { it.name.startsWith("cinterop") }.configureEach {
    dependsOn(swiftBuild, generateKotlinNativeBindings, generateCinteropDef)
}
tasks.matching { it.name == "compileKotlinMacosArm64" }.configureEach {
    dependsOn(generateKotlinNativeBindings)
}

// Convenience alias so the demo runs like the KotlinFFM sample's `run`:
//   ./gradlew :Samples:KotlinNativeSampleApp:run
tasks.register("run") {
    group = "application"
    description = "Run the Kotlin/Native demo (macosArm64)"
    dependsOn("runDebugExecutableMacosArm64")
}
