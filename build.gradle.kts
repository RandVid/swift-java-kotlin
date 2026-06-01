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

// Load the Kotlin plugins into the root project's (shared parent) classloader
// scope without applying them here. This lets the sibling sample projects
// (Kotlin/JVM and Kotlin/Native) share a single KotlinNativeBundleBuildService
// instead of each loading the plugin in its own scope, which otherwise fails
// with a conflicting-classloader error on the native link task.
// Versions are provided centrally via pluginManagement in settings.gradle.kts.
plugins {
    kotlin("jvm") apply false
    kotlin("multiplatform") apply false
}
