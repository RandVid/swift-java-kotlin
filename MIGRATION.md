# Migration Plan: Add a Kotlin/Native generation mode to swift-java

## Context

Today the project's `--mode kotlin` emits Kotlin **JVM** source that delegates to generated **Java FFM** classes
(`Kotlin → Java FFM → Swift`). That path needs JDK 25, `java.lang.foreign`, `--enable-native-access`, and
`java.library.path`/`DYLD_LIBRARY_PATH` wiring — all JVM-bound.

We want a **Kotlin/Native** path that calls Swift directly, with **no JVM in the loop**. The key enabler (verified
against real build artifacts): the FFM pipeline already emits Swift `@_cdecl` C thunks, and the SwiftPM plugin's
generated header `SimpleSwiftLib-Swift.h` declares each one as a plain C function, e.g.

```c
SWIFT_EXTERN NSInteger swiftjava_SimpleSwiftLib_add_a_b(NSInteger a, NSInteger b) SWIFT_NOEXCEPT SWIFT_WARN_UNUSED_RESULT;
SWIFT_EXTERN void      swiftjava_SimpleSwiftLib_helloWorld(void) SWIFT_NOEXCEPT;
```

`nm -gU libSimpleSwiftLib.dylib` shows `_swiftjava_SimpleSwiftLib_add_a_b` etc. exported as unmangled global symbols.
**Kotlin/Native cinterop can consume that header and link those symbols directly** — bypassing the JVM and Java FFM
entirely while reusing 100% of the existing Swift thunk generation.

**Decisions (confirmed with user):** add a NEW mode alongside the existing one (don't touch `kotlin`/JVM or
`KotlinFFMSampleApp`); target **macosArm64 only** initially; structure the integration as a new
**Kotlin Multiplatform** sample `Samples/KotlinNativeSampleApp`.

**Intended outcome:** `swift-java jextract --mode kotlinNative` generates Kotlin/Native wrappers that call the Swift
`@_cdecl` thunks via cinterop; a KMP sample compiles and runs them on macOS arm64; full primitive coverage
(all signed and unsigned integer widths, Bool, Float, Double, Void, String).

---

## Implementation status

Phases 0–5 are **done and verified** (`./gradlew :Samples:KotlinNativeSampleApp:macosArm64Test` passes, executing real
Swift through cinterop). Signed primitive coverage has since been expanded beyond the original Int/Int32/Bool/Double
set — see *Primitive expansion* below.

Three findings during implementation changed the original plan:

1. **The SwiftPM `<Module>-Swift.h` cannot be used by cinterop.** Its `swiftjava_*` thunks sit behind
   `#if defined(__OBJC__)` and under `#pragma clang attribute push(external_source_symbol(language="Swift", ...))`,
   so cinterop treats them as Swift (not C) declarations and emits no bindings (even with `language = Objective-C`,
   which only pulls in Foundation noise). **Resolution:** the generator emits its own clean plain-C header
   `<Module>.h` (via the otherwise-unused `--output-swift` dir); the `.def` binds against that in plain-C mode.
2. **Two sibling Gradle projects applying the Kotlin plugin conflict** over the shared
   `KotlinNativeBundleBuildService` (the JVM `KotlinFFMSampleApp` vs the new MPP sample). **Resolution:** a root
   `build.gradle.kts` declaring `kotlin("jvm"/"multiplatform") apply false` + versions centralized in
   `settings.gradle.kts` `pluginManagement.plugins {}`, loading the plugin in the shared root classloader scope.
   The existing FFM sample is untouched and still builds.
3. **`Bool` → `BOOL` → Kotlin `Boolean`** is confirmed (the open question from the original plan): with the clean-C
   header declaring `_Bool`, cinterop binds it to `Boolean` and pass-through works — no conversion code needed.

**String parameters and String returns are both now supported.** Parameters: the C declaration comes from FFM's
`CdeclLowering` (`String` → `UnsafePointer<Int8>` → `const int8_t *`); the Kotlin wrapper passes `name.cstr` (a
null-terminated UTF-8 buffer cinterop pins for the call), matching the thunk's `String(cString:)`. Returns: the thunk
hands back a heap-allocated `int8_t *` from `_swiftjava_stringToCString(...)`; the generated wrapper captures the
pointer, copies it via `.toKString()`, calls `free(ptr)` (`import platform.posix.free`), and returns the Kotlin
`String`. Phase 5 is complete.

### Design decision: the cinterop C header (must generate; should reuse FFM's C lowering)

A recurring question is whether `kotlinNative` can avoid generating its own C header by reusing existing output.
There are two distinct "reuses", with opposite answers:

- **Reuse the Swift-compiler-emitted `<Module>-Swift.h` → not possible.** That header (produced by `swift build`'s
  `-emit-clang-header`, *not* by jextract) marks every thunk with
  `#pragma clang attribute push(external_source_symbol(language="Swift", …))`, so cinterop classifies them as Swift
  declarations and emits zero bindings. There is no cinterop flag to override this filter and no Swift flag to
  suppress the attribute. The only workaround is to `sed` the pragma/`#if defined(__OBJC__)` guards out of the header
  at build time — fragile (coupled to the compiler's exact header format, version-dependent) and strictly worse than
  emitting clean declarations from the IR. **Do not pursue.**

- **Reuse FFM/JNI's C-ABI lowering machinery → yes, and we should.** FFM already lowers every thunk to a `CFunction`
  (`Sources/JExtractSwiftLib/CTypes/` + `FFM/CDeclLowering/CRepresentation.swift`), whose `.description` prints a
  complete C declaration (`long swiftjava_…(long, long);`) for *all* cdecl types — pointers, optional-pointers,
  indirect struct returns, self-pointers — not just primitives. This is the same lowering that produces FFM's Java
  `FunctionDescriptor`, i.e. the single source of truth for the C ABI.

**Conclusion:** generating a clean plain-C header is **unavoidable** (cinterop cannot consume the Swift one). The open
choice is only *what derives the C types*. The current generator uses a bespoke `swiftTypeToC` covering the 5
primitives; it matches FFM exactly today, so primitive output is correct, but it duplicates ABI knowledge. **Planned
improvement:** replace `swiftTypeToC` (and the hand-built prototype string) with FFM's cdecl→`CFunction` lowering and
emit `cFunction.description`. This keeps one C-ABI source of truth across FFM/JNI/kotlinNative and is a **prerequisite
for non-primitive support** (Phase 5), where the cdecl thunk signature is not a 1:1 type map (it adds out-pointers for
indirect returns and self-pointers) and hand-rolling would produce wrong signatures.

### Build decision: cinterop runs from a locally-built Kotlin/Native distribution

For the migration the sample builds cinterop against a **local** Kotlin/Native dist
(`~/IdeaProjects/kotlin/kotlin-native/dist`) instead of the one the Kotlin Gradle plugin auto-downloads
(`~/.konan/kotlin-native-prebuilt-…`). The redirect is the standard `kotlin.native.home` Gradle property; the plugin
then resolves the cinterop executable from `<kotlin.native.home>/bin/cinterop` and logs *"A user-provided
Kotlin/Native distribution configured … Disabling Kotlin Native Toolchain auto-provisioning."*

Constraints found while wiring this:
- The plugin reads `kotlin.native.home` as a **real Gradle property at apply time** — it does *not* see
  `extraProperties` injected from the build script (verified: a script-injected value still triggered the bundle
  download), and a subproject `gradle.properties` is ignored by Gradle. The value must therefore live in a real Gradle
  properties file (`~/.gradle/gradle.properties` or the repo root) or be passed via `-Pkotlin.native.home=<dist>`.
- It is set **machine-local and uncommitted** in `~/.gradle/gradle.properties`, so no absolute path lands in the repo
  and CI / other contributors are unaffected (tradeoff: it then applies to *all* K/N Gradle projects on the machine;
  move it to the repo-root `gradle.properties` to scope it to this repo at the cost of committing the path).
- This swaps the **entire** K/N toolchain — the plugin has no supported way to override only the cinterop binary.
- `Samples/KotlinNativeSampleApp/build.gradle.kts` adds a fail-fast guard: when `kotlin.native.home` is set it
  verifies `<dist>/bin/cinterop` exists, failing with a clear message rather than letting cinterop blow up later.
- The typed `tasks.withType<CInteropProcess>()` wiring was replaced with name-based matching
  (`tasks.matching { it.name.startsWith("cinterop") }`), dropping the
  `import org.jetbrains.kotlin.gradle.tasks.CInteropProcess`.

---

## Current-state findings (confirmed)

- **Modes:** `Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift` — enum `ffm`/`jni`/`kotlin`, default `.ffm`.
- **Dispatch:** `Sources/JExtractSwiftLib/Swift2Java.swift:123` — exhaustive `switch config.effectiveMode` instantiating each generator.
- **Existing Kotlin/JVM generator:** `Sources/JExtractSwiftLib/Kotlin/KotlinSwift2KotlinGenerator.swift` — emits one `<Module>.kt` of top-level funcs delegating to a Java FFM class; reuses `--output-java` (dir) and `--java-package` (package); primitives only; skips String returns / async / members / unsupported with `// Skipped …` comments.
- **Thunk names:** `Sources/JExtractSwiftLib/ThunkNameRegistry.swift` + `Sources/JExtractSwiftLib/FFM/FFMSwift2JavaGenerator+SwiftThunkPrinting.swift` produce `swiftjava_<module>_<name>[_<labels>]`. These C symbols + the `-Swift.h` header are emitted by the SwiftPM `JExtractSwiftPlugin` during `swift build` (same as the FFM sample).
- **C type mapping in the header:** Swift `Int`→`ptrdiff_t`→cinterop `Long`; `Int8`→`int8_t`→`Byte`; `Int16`→`int16_t`→`Short`; `Int32`→`int32_t`→`Int`; `Int64`→`int64_t`→`Long`; `UInt`→`size_t`→`ULong`; `UInt8`→`uint8_t`→`UByte`; `UInt16`→`uint16_t`→`UShort`; `UInt32`→`uint32_t`→`UInt`; `UInt64`→`uint64_t`→`ULong`; `Bool`→`_Bool`→`Boolean` (confirmed, no conversion code needed); `Float`→`float`→`Float`; `Double`→`double`→`Double`; `void`→`Unit`.
- **Test harness:** `Tests/JExtractSwiftTests/Asserts/TextAssertions.swift` `assertOutput(…)` dispatches by `(mode, RenderKind)`; JVM Kotlin tests live in `Tests/JExtractSwiftTests/Kotlin/KotlinTopLevelFunctionsTests.swift` asserting exact `.kt` chunks.
- **Build:** Gradle 9.4.0, Kotlin plugin 2.3.10. `settings.gradle.kts` auto-discovers `Samples/*` containing `build.gradle.kts` (unless `-PskipSamples`). `BuildLogic/src/main/kotlin/utilities/registerJextractTask.kt` registers the `swift build` task; `javaLibraryPaths.kt`/`SwiftcTargetInfo.kt` can compute Swift runtime paths via `swiftc -print-target-info`.
- **CI:** `.github/workflows/pull_request.yml` has `verify-samples` (Linux) and `verify-samples-macos` (self-hosted macOS ARM64). `KotlinFFMSampleApp` is NOT in either matrix. No Kotlin/Native scaffolding exists anywhere (no KMP, no cinterop, no `.def`).

---

## Proposed architecture

```
Swift source ──swift build (SwiftPM JExtractSwiftPlugin)──▶ libSimpleSwiftLib.dylib + SimpleSwiftLib-Swift.h
                                                              (existing @_cdecl C thunks — REUSED)
                                                                        │
swift-java jextract --mode kotlinNative ──▶ <Module>.kt   cinterop(.def → header) ──▶ klib bindings
   (new KotlinNativeSwift2KotlinGenerator)      │                                          │
                                                └────────── import + call ─────────────────┘
                                                                        │
                                              Kotlin/Native test/exe binary calls Swift directly
```

The Swift-side generator stays **pure**: it emits only the `.kt` wrappers (reusing the JVM generator's type-mapping
and skip logic, swapping the call target from `Module.fn(args)` to the bare C symbol `swiftjava_…(args)`). All
host-specific path wiring (the cinterop `.def` with `-I`/`-L`/`-rpath`) lives in **Gradle**, where paths are known.

---

## Step-by-step implementation plan (phased, each phase independently buildable)

### Phase 0 — Enum + dispatch skeleton
- `JExtractGenerationMode.swift`: add `case kotlinNative` (raw value `"kotlinNative"`, consistent with the bare `kotlin` case).
- `Swift2Java.swift:123`: add a `case .kotlinNative:` arm (delegating to the new generator; initially a stub emitting an empty `<Module>.kt`).
- `TextAssertions.swift`: add a `case .kotlinNative:` arm to the mode switch (mirror the `.kotlin` arm: `.java` renderKind → new generator's `writeExportedKotlinSources`; `.swift` → FFM `writeSwiftThunkSources`).
- ✅ `swift build` + existing `swift test` stay green; new mode produces an empty file.

### Phase 1 — Primitive-only generator + unit tests (no Gradle)
- NEW `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift`, modeled on `KotlinSwift2KotlinGenerator` (same init: `config`, `translator`, `kotlinPackage`, `kotlinOutputDirectory`).
  - Reuse the JVM generator's `swiftTypeToKotlin` mapping, parameter rendering, keyword escaping, and all `// Skipped …` guards (`apiKind == .function`, `hasParent == false`, `isAsync == false`, String-return skip).
  - **Only difference:** the call line. Instead of `Module.<name>(args)`, emit the bare C symbol obtained from `ThunkNameRegistry.functionThunkName(decl:)` (reuse the registry — do not hand-build names) so the Kotlin call matches the exported symbol exactly.
  - Emit deterministic `import`s from a known cinterop package: set it to `<kotlinPackage>.cinterop` so imports are `import <pkg>.cinterop.swiftjava_…`.
  - Sketch output (`add(a: Int, b: Int) -> Int`, `helloWorld()`):
    ```kotlin
    package com.example.kotlinnative
    import com.example.kotlinnative.cinterop.swiftjava_SimpleSwiftLib_add_a_b
    import com.example.kotlinnative.cinterop.swiftjava_SimpleSwiftLib_helloWorld

    fun add(a: Long, b: Long): Long {
      return swiftjava_SimpleSwiftLib_add_a_b(a, b)
    }
    fun helloWorld(): Unit {
      swiftjava_SimpleSwiftLib_helloWorld()
    }
    ```
- NEW `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift`, mirroring the JVM test file but asserting the direct-C-call form and the `swiftjava_<module>_<name>_<labels>` thunk names. Reuse identical skip-case assertions.
- ✅ `swift test` validates exact `.kt` text; no native toolchain needed.

### Phase 2 — Sample Swift lib (dylib + header), no Kotlin compile yet
- NEW `Samples/KotlinNativeSampleApp/`:
  - `Package.swift` — near-verbatim copy of `Samples/KotlinFFMSampleApp/Package.swift` (rename to `KotlinNativeSampleApp`, same dynamic `SimpleSwiftLib` product, same `JExtractSwiftPlugin`, `.macOS(.v15)`).
  - `Sources/SimpleSwiftLib/SimpleSwiftLib.swift` — copy the FFM sample's primitive-only funcs (parity).
  - `Sources/SimpleSwiftLib/swift-java.config` — `{ "javaPackage": "com.example.kotlinnative", "logLevel": "info" }`.
- `settings.gradle.kts`: add an **OS guard** so this module is skipped on non-macOS hosts (key on `System.getProperty("os.name")`), additive to the existing `skipped` logic — keeps Linux `./gradlew build` green since `macosArm64` can't build there.
- ✅ `swift build` in the sample produces `libSimpleSwiftLib.dylib` + `SimpleSwiftLib-Swift.h` with the `swiftjava_*` prototypes (same plugin as FFM sample).

### Phase 3 — Gradle KMP wiring + integration test (macOS arm64)
- NEW `Samples/KotlinNativeSampleApp/build.gradle.kts` with `kotlin("multiplatform") version "2.3.10"`:
  - `macosArm64 { … }` target with a `cinterops { create("SimpleSwiftLib") { defFile(...) } }` block.
  - `registerJextractTask()` (reused) to run `swift build` (produces dylib + header).
  - `generateKotlinNativeBindings` `Exec` task → runs `swift-java jextract … --mode kotlinNative --output-java build/kotlin-native-generated/kotlin --java-package com.example.kotlinnative` (pass a throwaway `--output-swift` dir to satisfy the run() guard; it's unused here). Add generated dir via `kotlin.srcDir(...)` on `macosArm64Main`.
  - `generateCinteropDef` task → Gradle writes `native/SimpleSwiftLib.def` with resolved absolute paths:
    ```
    package = com.example.kotlinnative.cinterop
    headers = SimpleSwiftLib-Swift.h
    compilerOpts = -I<…>/.build/arm64-apple-macosx/debug/SimpleSwiftLib.build/include
    linkerOpts = -L<…>/.build/arm64-apple-macosx/debug -lSimpleSwiftLib -L/usr/lib/swift -rpath <…>/debug -rpath /usr/lib/swift
    ```
    Prefer computing `/usr/lib/swift` (and the SPM debug dir) via the existing `swiftRuntimeLibraryPaths()` helper rather than hardcoding. This **replaces** the JVM path's `DYLD_LIBRARY_PATH`/`java.library.path` — symbols resolve through the native linker + baked rpath, no env vars at run time.
  - Task deps: cinterop `dependsOn(jextract, generateCinteropDef)`; `compileKotlinMacosArm64 dependsOn generateKotlinNativeBindings`.
  - `macosArm64Test` source set: `implementation(kotlin("test"))`.
- NEW `Samples/KotlinNativeSampleApp/src/nativeTest/kotlin/SimpleSwiftLibTest.kt` — `@Test` cases calling `add/isPositive/divide` and asserting real Swift results (true end-to-end through cinterop).
- ✅ `./gradlew :Samples:KotlinNativeSampleApp:macosArm64Test` on macOS arm64: builds dylib → generates `.kt` → cinterop → links → runs tests against real Swift.

### Phase 4 — CI
- Add `KotlinNativeSampleApp` to the **`verify-samples-macos`** matrix ONLY (not the Linux `verify-samples` — cinterop/macosArm64 require the macOS SDK + konan toolchain).
- Add `Samples/KotlinNativeSampleApp/ci-validate.sh` mirroring `KotlinFFMSampleApp/ci-validate.sh` (swift build, then `gradlew :…:macosArm64Test`), or confirm `.github/scripts/validate_sample.sh` handles a KMP module.

### Phase 5 — ✅ strings / allocating returns (done)
- String params: passed via `.cstr` (null-terminated UTF-8; cinterop pins during call). String returns: thunk returns a heap `int8_t *`; generated wrapper does `ptr.toKString()` then `free(ptr)` (via `import platform.posix.free`).

### Primitive expansion — ✅ signed (Int8 / Int16 / Int64 / Float) and unsigned (UInt / UInt8 / UInt16 / UInt32 / UInt64) (done)
- `KotlinNativeSwift2KotlinGenerator.swiftTypeToKotlin` extended to cover all integer widths and `Float`:

  | Swift    | C (`@_cdecl`) | Kotlin    |
  |----------|--------------|-----------|
  | `Int`    | `ptrdiff_t`  | `Long`    |
  | `Int8`   | `int8_t`     | `Byte`    |
  | `Int16`  | `int16_t`    | `Short`   |
  | `Int32`  | `int32_t`    | `Int`     |
  | `Int64`  | `int64_t`    | `Long`    |
  | `UInt`   | `size_t`     | `ULong`   |
  | `UInt8`  | `uint8_t`    | `UByte`   |
  | `UInt16` | `uint16_t`   | `UShort`  |
  | `UInt32` | `uint32_t`   | `UInt`    |
  | `UInt64` | `uint64_t`   | `ULong`   |
  | `Bool`   | `_Bool`      | `Boolean` |
  | `Float`  | `float`      | `Float`   |
  | `Double` | `double`     | `Double`  |
  | `String` | `int8_t *`   | `String`  |
  | `Void`   | `void`       | `Unit`    |

  Note: `UInt` and `UInt64` both map to `ULong` (Swift's `UInt` is pointer-sized = 64-bit on arm64). Kotlin unsigned types are stable since Kotlin 1.5; no opt-in annotation is required.
- The `CdeclLowering` / `CRepresentation` machinery already handled all these C types; only the Kotlin-side mapping was missing in both passes.
- Signed expansion: 9 new unit tests; `addInt8/addInt16/addInt64/addFloat` in the sample lib.
- Unsigned expansion: 10 new unit tests (parameter + return per type); `addUInt8/addUInt16/addUInt32/addUInt64` in the sample lib; demo items 11–14; integration test assertions with `u`/`uL` literals and `.toUByte()`/`.toUShort()` casts.

---

## Files to create / modify

**Modify (Swift core):**
- `Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift` — add `.kotlinNative`.
- `Sources/JExtractSwiftLib/Swift2Java.swift` — dispatch arm (~line 123).
- `Tests/JExtractSwiftTests/Asserts/TextAssertions.swift` — `assertOutput` dispatch arm.

**Create (Swift core + tests):**
- `Sources/JExtractSwiftLib/KotlinNative/KotlinNativeSwift2KotlinGenerator.swift`.
- `Tests/JExtractSwiftTests/KotlinNative/KotlinNativeTopLevelFunctionsTests.swift`.

**Create (sample, all under `Samples/KotlinNativeSampleApp/`):**
- `Package.swift`, `Sources/SimpleSwiftLib/SimpleSwiftLib.swift`, `Sources/SimpleSwiftLib/swift-java.config`.
- `build.gradle.kts`, `src/nativeTest/kotlin/SimpleSwiftLibTest.kt`, `ci-validate.sh`, `README.md`.
- (`native/SimpleSwiftLib.def` is generated by Gradle, not checked in.)

**Modify (build/CI):**
- `settings.gradle.kts` — OS guard for the macOS-only sample.
- `.github/workflows/pull_request.yml` — add sample to `verify-samples-macos`.

**Reuse (read-only):** `ThunkNameRegistry.swift`, `FFMSwift2JavaGenerator+SwiftThunkPrinting.swift`, `BuildLogic/.../{registerJextractTask,javaLibraryPaths,SwiftcTargetInfo}.kt`.

---

## Verification

- **Unit (no native toolchain):** `swift build --disable-experimental-prebuilts` then `swift test --filter KotlinNative` — asserts generated `.kt` text and skip comments; full `swift test` stays green (Phase 0–1).
- **Generator smoke:** `swift run swift-java jextract --swift-module SimpleSwiftLib --input-swift Samples/KotlinNativeSampleApp/Sources/SimpleSwiftLib --output-swift /tmp/kn-swift --output-java /tmp/kn-kotlin --java-package com.example.kotlinnative --mode kotlinNative` → inspect emitted `<Module>.kt`.
- **Integration (macOS arm64):** `cd Samples/KotlinNativeSampleApp && ./ci-validate.sh` (or `./gradlew :Samples:KotlinNativeSampleApp:macosArm64Test`) — exercises dylib build → cinterop → link → Kotlin/Native tests calling real Swift.
- **Cross-platform safety:** `./gradlew build -PskipSamples=true` and a Linux `./gradlew build` must remain green (OS guard skips the macOS-only module).
- **Parity:** `add/isPositive/divide/helloWorld/printMessage/greet` all work end-to-end. (`greet` returns a `String`; the kotlinNative wrapper calls `toKString()` + `free()`; the JVM Kotlin delegation mode still skips String returns.) `addInt8/addInt16/addInt64/addFloat` exercise signed primitives; `addUInt8/addUInt16/addUInt32/addUInt64` exercise unsigned primitives — all verified through the full cinterop stack.

---

## Risks & open questions

1. **`Bool` cinterop mapping — resolved.** `_Bool` (from the clean-C header) maps to Kotlin `Boolean` with no conversion code needed. cinterop generates a direct pass-through for `isPositive`.
2. **Swift runtime linking / rpath (highest integration effort).** dylib needs `@rpath/libSwiftJava.dylib`, `@rpath/libSwiftRuntimeFunctions.dylib`, `/usr/lib/swift/libswiftCore.dylib`. `.def` `linkerOpts` must carry `-L` for the SPM debug dir + `/usr/lib/swift` and baked `-rpath`. Prefer `swiftRuntimeLibraryPaths()` over hardcoding.
3. **Header path is config-specific.** `-I …/debug/SimpleSwiftLib.build/include` assumes a debug build; parameterize if release is ever used. cinterop must depend on the def-generation + `swift build` tasks.
4. **Toolchain availability.** cinterop needs a Kotlin/Native toolchain + Xcode CLT for the macOS SDK headers — present only on the self-hosted macOS runner; hence CI placement and the Linux OS guard. Local development points `kotlin.native.home` at a locally-built dist (see *Build decision* above); CI, with no such property set, falls back to the KMP-plugin-fetched konan bundle. Confirm the runner has CLT and konan can be fetched/cached (or set `kotlin.native.home` there too).
5. **`@_cdecl` symbol stability — confirmed non-issue.** `nm -gU` shows unmangled exported symbols; cinterop binds by C name from the header; the `jextract`/`swift build` task dependency keeps dylib and `.def` in sync.

### Open questions for the team (non-blocking)
- CLI raw-value spelling: `kotlinNative` (consistent with bare `kotlin`) vs `kotlin-native`.
- Whether to later unify "language" (kotlin) vs "backend" (jvm/native) instead of stacking modes — noted in DESIGN.md technical debt; out of scope here.
