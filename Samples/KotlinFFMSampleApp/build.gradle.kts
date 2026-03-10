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

import utilities.javaLibraryPaths
import utilities.registerJextractTask

plugins {
    id("build-logic.java-application-conventions")
    kotlin("jvm") version "2.3.10"
}

group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

dependencies {
    implementation(kotlin("stdlib"))
}

// Register jextract task for Java FFM generation
val jextract = registerJextractTask()

// Custom task to generate Kotlin bindings
val generateKotlinBindings = tasks.register<Exec>("generateKotlinBindings") {
    description = "Generate Kotlin bindings using jextract with kotlin mode"

    workingDir = rootDir

    // Set DYLD_LIBRARY_PATH to include Swift runtime libraries
    val swiftLibPath = "/usr/lib/swift"
    environment("DYLD_LIBRARY_PATH", swiftLibPath)

    commandLine = listOf(
        ".build/arm64-apple-macosx/debug/swift-java",
        "jextract",
        "--swift-module", "SimpleSwiftLib",
        "--input-swift", "Samples/KotlinFFMSampleApp/Sources/SimpleSwiftLib",
        "--output-swift", "Samples/KotlinFFMSampleApp/.build/kotlin-generated/swift",
        "--output-java", "Samples/KotlinFFMSampleApp/.build/kotlin-generated/kotlin",
        "--java-package", "com.example.kotlinffm",
        "--mode", "kotlin"
    )

    // Inputs and outputs for up-to-date checking
    inputs.dir("Sources/SimpleSwiftLib")
    outputs.dir(".build/kotlin-generated/kotlin")

    // Only run if swift-java binary exists
    onlyIf {
        file("${rootDir}/.build/arm64-apple-macosx/debug/swift-java").exists()
    }
}

// Add the generated sources to source sets
sourceSets {
    main {
        java {
            srcDir(jextract)
        }
        kotlin {
            srcDir(".build/kotlin-generated/kotlin")
        }
    }
    test {
        java {
            srcDir(jextract)
        }
    }
}

// Make sure jextract runs before compiling
tasks.compileJava {
    dependsOn(jextract)
}

// Make sure Kotlin generation runs before compiling Kotlin
tasks.compileKotlin {
    dependsOn(jextract, generateKotlinBindings)
}

tasks.build {
    dependsOn(jextract, generateKotlinBindings)
}

registerCleanSwift()

dependencies {
    implementation(projects.swiftKitCore)
    implementation(projects.swiftKitFFM)

    testRuntimeOnly(libs.junit.platform.launcher)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
}

tasks.named<Test>("test") {
    useJUnitPlatform()

    // Add JVM args for FFM
    jvmArgs(
        "--enable-native-access=ALL-UNNAMED",
        "-Djava.library.path=" + (javaLibraryPaths(rootDir) + javaLibraryPaths(project.projectDir)).joinToString(":")
    )
}

application {
    mainClass = "com.example.kotlinffm.KotlinFFMDemo"

    applicationDefaultJvmArgs = listOf(
        "--enable-native-access=ALL-UNNAMED",
        "-Djava.library.path=" + (javaLibraryPaths(rootDir) + javaLibraryPaths(project.projectDir)).joinToString(":")
    )
}
