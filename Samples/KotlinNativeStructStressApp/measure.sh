#!/bin/bash
# Stress-test measurement harness for the kotlinNative struct pipeline.
# For each N (args), regenerates N structs and times each pipeline phase:
#   gen    - raw `swift-java jextract` generator run (Kotlin wrappers + thunks)
#   swift  - `swift build` (SwiftPM plugin thunk regen + dylib compile/link)
#   kotlinc- Kotlin/Native compilation of the generated wrappers + driver
#   link   - Kotlin/Native native link into the executable
#   run    - direct execution of the produced .kexe
#
# Usage: ./measure.sh 10 100 1000
# Failure-tolerant: if a phase fails (e.g. compiler OOM at very large N), that
# cell and the dependent phases are recorded as FAIL and the sweep continues.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOOL="$ROOT/.build/arm64-apple-macosx/debug/swift-java"
GRADLE="$ROOT/gradlew"
PROJ=":Samples:KotlinNativeStructStressApp"
KEXE="$HERE/build/bin/macosArm64/debugExecutable/KotlinNativeStructStressApp.kexe"
REL="Samples/KotlinNativeStructStressApp"

now() { python3 -c 'import time;print("%.3f"%time.time())'; }
elapsed() { python3 -c "print('%.2f'%($2-$1))"; }

printf "%6s | %8s | %8s | %8s | %8s | %8s\n" N gen swift kotlinc link run
printf -- "-------+----------+----------+----------+----------+----------\n"

for N in "$@"; do
  python3 "$HERE/gen.py" "$N" >/dev/null
  failed=0
  # timed <label> <cmd...> : echo elapsed, or FAIL (and latch `failed`) on error.
  timed() {
    if [ "$failed" = "1" ]; then echo "-"; return; fi
    local t0 t1
    t0=$(now)
    if "$@" >/dev/null 2>&1; then t1=$(now); elapsed "$t0" "$t1"; else failed=1; echo "FAIL"; fi
  }
  jextract() { ( cd "$ROOT" && DYLD_LIBRARY_PATH=/usr/lib/swift "$TOOL" jextract \
      --swift-module StressLib --input-swift "$REL/Sources/StressLib" \
      --output-swift "$REL/.build/kotlin-native-generated/swift" \
      --output-java "$REL/.build/kotlin-native-generated/kotlin" \
      --java-package com.example.stress --mode kotlinNative ); }
  gtask() { ( cd "$ROOT" && "$GRADLE" "$PROJ:$1" -q ); }

  T_gen=$(timed jextract)                                   # 1. raw generator
  gtask generateKotlinNativeBindings >/dev/null 2>&1        # prime up-to-date
  T_swift=$(timed gtask swiftBuild)                         # 2. swift dylib
  T_kotlinc=$(timed gtask compileKotlinMacosArm64)          # 3. KN compile
  T_link=$(timed gtask linkDebugExecutableMacosArm64)       # 4. KN link
  T_run=$(timed "$KEXE")                                    # 5. runtime

  printf "%6s | %8s | %8s | %8s | %8s | %8s\n" "$N" "$T_gen" "$T_swift" "$T_kotlinc" "$T_link" "$T_run"
done
