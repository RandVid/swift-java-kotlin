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
`@_cdecl` thunks via cinterop; a KMP sample compiles and runs them on macOS arm64; parity with the JVM mode's
primitive-only surface (Int/Int32/Bool/Double/Void).

---

## Implementation status

Phases 0–4 are **done and verified** (`./gradlew :Samples:KotlinNativeSampleApp:macosArm64Test` passes, executing real
Swift through cinterop). Phase 5 (String / allocating returns) remains, deferred as below.

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
   String params/returns are skipped for now (Kotlin/Native needs explicit `memScoped` conversion — Phase 5).

---

## Current-state findings (confirmed)

- **Modes:** `Sources/SwiftJavaConfigurationShared/JExtract/JExtractGenerationMode.swift` — enum `ffm`/`jni`/`kotlin`, default `.ffm`.
- **Dispatch:** `Sources/JExtractSwiftLib/Swift2Java.swift:123` — exhaustive `switch config.effectiveMode` instantiating each generator.
- **Existing Kotlin/JVM generator:** `Sources/JExtractSwiftLib/Kotlin/KotlinSwift2KotlinGenerator.swift` — emits one `<Module>.kt` of top-level funcs delegating to a Java FFM class; reuses `--output-java` (dir) and `--java-package` (package); primitives only; skips String returns / async / members / unsupported with `// Skipped …` comments.
- **Thunk names:** `Sources/JExtractSwiftLib/ThunkNameRegistry.swift` + `Sources/JExtractSwiftLib/FFM/FFMSwift2JavaGenerator+SwiftThunkPrinting.swift` produce `swiftjava_<module>_<name>[_<labels>]`. These C symbols + the `-Swift.h` header are emitted by the SwiftPM `JExtractSwiftPlugin` during `swift build` (same as the FFM sample).
- **C type mapping in the header:** Swift `Int`→`NSInteger`(64-bit)→cinterop `Long`; `Int32`→`int`→`Int`; `Bool`→`BOOL`→`Boolean` (to be verified, see Risks); `Double`→`double`→`Double`; `void`→`Unit`.
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

### Phase 5 — (later, out of initial scope) strings / allocating returns
- String params via `memScoped { … cstr … }`; String returns via the `int8_t*`-returning thunk → `toKString()` → free with the `SwiftRuntimeFunctions`/SwiftKit free symbol. Phase 1 deliberately skips strings exactly like the JVM mode does today.

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
- **Parity:** same `SimpleSwiftLib.swift` as the JVM sample; confirm `add/isPositive/divide/helloWorld/printMessage` behave identically and `greet` (String return) is `// Skipped` in both modes.

---

## Risks & open questions

1. **`BOOL` cinterop mapping (verify in Phase 3).** Expected `Boolean` pass-through on Apple targets, but `BOOL` may surface as `Byte`. If so, the generator emits `if (x) 1 else 0` inbound / `result != 0` outbound. Inspect cinterop's generated signatures for `isPositive`; make Bool handling conditional on the verified mapping. *(One type may need conversion code; everything else passes through.)*
2. **Swift runtime linking / rpath (highest integration effort).** dylib needs `@rpath/libSwiftJava.dylib`, `@rpath/libSwiftRuntimeFunctions.dylib`, `/usr/lib/swift/libswiftCore.dylib`. `.def` `linkerOpts` must carry `-L` for the SPM debug dir + `/usr/lib/swift` and baked `-rpath`. Prefer `swiftRuntimeLibraryPaths()` over hardcoding.
3. **Header path is config-specific.** `-I …/debug/SimpleSwiftLib.build/include` assumes a debug build; parameterize if release is ever used. cinterop must depend on the def-generation + `swift build` tasks.
4. **Toolchain availability.** cinterop needs the konan toolchain (fetched by KMP plugin) + Xcode CLT for the macOS SDK headers — present only on the self-hosted macOS runner; hence CI placement and the Linux OS guard. Confirm the runner has CLT and konan can be fetched/cached.
5. **`@_cdecl` symbol stability — confirmed non-issue.** `nm -gU` shows unmangled exported symbols; cinterop binds by C name from the header; the `jextract`/`swift build` task dependency keeps dylib and `.def` in sync.

### Open questions for the team (non-blocking)
- CLI raw-value spelling: `kotlinNative` (consistent with bare `kotlin`) vs `kotlin-native`.
- Whether to later unify "language" (kotlin) vs "backend" (jvm/native) instead of stacking modes — noted in DESIGN.md technical debt; out of scope here.
