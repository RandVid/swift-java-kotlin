#!/bin/bash

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
