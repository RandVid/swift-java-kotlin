//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import org.jetbrains.kotlin.gradle.tasks.CInteropProcess

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
        // --output-swift is required by the CLI but unused in kotlinNative mode
        // (the Swift thunks come from the SwiftPM plugin during `swift build`).
        "--output-swift", "Samples/KotlinNativeSampleApp/.build/kotlin-native-generated/swift",
        "--output-java", "Samples/KotlinNativeSampleApp/build/kotlin-native-generated/kotlin",
        "--java-package", "com.example.kotlinnative",
        "--mode", "kotlinNative"
    )
    inputs.dir("Sources/SimpleSwiftLib")
    outputs.dir(generatedKotlinDir)
    onlyIf { file(swiftJavaTool).exists() }
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
tasks.withType<CInteropProcess>().configureEach {
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
