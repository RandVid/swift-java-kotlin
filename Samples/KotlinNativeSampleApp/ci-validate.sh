#!/bin/bash
#===----------------------------------------------------------------------===//
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift.org project authors
# Licensed under Apache License v2.0
#
# See LICENSE.txt for license information
# See CONTRIBUTORS.txt for the list of Swift.org project authors
#
# SPDX-License-Identifier: Apache-2.0
#
#===----------------------------------------------------------------------===//

set -e
set -x

# Build the root swift-java tool (used to generate the Kotlin/Native bindings).
cd ../..
swift build --disable-experimental-prebuilts
cd Samples/KotlinNativeSampleApp

# Build and test via Gradle (Kotlin Multiplatform, macosArm64). This will:
# 1. Build the Swift dynamic library + jextract header (swiftBuild)
# 2. Generate the Kotlin/Native wrappers + cinterop C header (--mode kotlinNative)
# 3. Generate the cinterop .def and run cinterop
# 4. Compile the Kotlin/Native sources and run the native test binary,
#    which calls real Swift through cinterop.
../../gradlew :Samples:KotlinNativeSampleApp:macosArm64Test

echo "✅ Kotlin/Native cinterop tests passed!"
