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

# Build Swift components
cd ../..
swift build --disable-experimental-prebuilts
cd Samples/KotlinFFMSampleApp

# Build and test via Gradle
# This will:
# 1. Generate Java FFM bindings
# 2. Generate Kotlin delegation wrappers
# 3. Compile everything
# 4. Run tests
../../gradlew clean build test

echo "✅ Kotlin FFM delegation tests passed!"
