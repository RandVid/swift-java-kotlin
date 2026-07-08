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

plugins {
    kotlin("multiplatform")
    `maven-publish`
}

group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"
base {
    archivesName = "swiftkit-kn"
}

repositories {
    mavenCentral()
}

kotlin {
    macosArm64()

    sourceSets {
        val macosArm64Main by getting {
            // COpaquePointer is part of the experimental cinterop API
            languageSettings.optIn("kotlinx.cinterop.ExperimentalForeignApi")
        }
        val macosArm64Test by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }
    }
}

publishing {
    publications.withType<MavenPublication>().configureEach {
        groupId = group as? String
        version = "1.0-SNAPSHOT"
    }
}
