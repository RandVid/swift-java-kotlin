# KotlinNativeStructStressApp

A stress-test sample for the `kotlinNative` jextract mode, focused on **structs**
and **`Inout<T>`**. It generates *N* identical Swift structs (`struct1`…`structN`,
all sharing the same property names `a`, `b` and method names `sum`, `scale`),
bridges them to Kotlin/Native, and exercises every one through `Inout<T>` mutation.

Each struct is:

```swift
public struct structK {
    public var a: Int
    public var b: Int
    public init(a: Int, b: Int) { self.a = a; self.b = b }
    public func sum() -> Int { a + b }                       // non-mutating -> value class
    public mutating func scale(by factor: Int) { a *= factor; b *= factor }  // -> Inout<structK>.scale
}
```

The driver exercises the full struct surface per type: value-class construction,
a read-only method (`sum`), a `mutating` method (`scale`) as an `Inout<structK>`
extension, and a settable stored property (`a`) as an `Inout<structK>.a` extension.

## Files

- `gen.py N` — regenerates `Sources/StressLib/StressLib.swift` (N structs, one file)
  and `src/macosArm64Main/kotlin/Driver.kt` (one exercise fn per struct + a `main`
  that asserts the total equals `15 * N`). Both generated files are git-ignored.
- `measure.sh 10 100 1000` — regenerates each N and times each pipeline phase.

## Running

```bash
# from repo root — build once, then drive a single N:
python3 Samples/KotlinNativeStructStressApp/gen.py 100
./gradlew :Samples:KotlinNativeStructStressApp:run

# full scaling sweep:
Samples/KotlinNativeStructStressApp/measure.sh 10 100 1000
```

## Measured scaling (macOS arm64, 12-core / 69 GB, idle machine)

Wall-clock seconds per phase (each `T_gen` is the raw `swift-java jextract` run;
the rest are the individual Gradle tasks):

| N     | gen    | swift  | kotlinc | link  | run  |
|-------|--------|--------|---------|-------|------|
| 10    | 0.38   | 7.17   | 5.88    | 5.93  | 0.74 |
| 30    | 0.70   | 7.25   | 4.51    | 4.54  | 0.83 |
| 100   | 1.87   | 8.12   | 4.92    | 6.14  | 0.75 |
| 300   | 6.15   | 14.94  | 12.17   | 12.93 | 0.89 |
| 1000  | 21.11  | 34.47  | 30.60   | 26.32 | 1.04 |
| 3000  | 105.22 | 122.59 | 193.52  | 68.58 | 1.37 |
| 10000 | *pending — see note* |||||

Growth is **not uniform**. Small-N rows for the Gradle phases are dominated by a
~5–8 s fixed cost (daemon + toolchain + fixed link cost); the per-N behaviour only
shows once N is large. Local log-log exponents on the top decade (300→3000):

| phase   | 300→3000 exponent | character                                   |
|---------|-------------------|---------------------------------------------|
| gen     | ~1.23 (1.46 on 1000→3000) | near-linear ≤1000, **super-linear ≥1000** |
| kotlinc | ~1.20 (1.68 on 1000→3000) | **the bottleneck — strongly super-linear** |
| swift   | ~0.91 (1.16 on 1000→3000) | ~linear, mild super-linearity at the top   |
| link    | ~0.72 (0.87 on 1000→3000) | ~linear, large fixed cost                   |
| run     | ~flat             | negligible                                  |

- **gen** (`swift-java jextract`) — near-linear up to ~1000 (~21 ms/struct at
  N=1000), then clearly **super-linear** (≈N^1.4–1.5) by N=3000, even though the
  emitted output is *exactly* linear (~67 Kotlin + ~56 Swift lines/struct;
  201,020 lines of Kotlin at N=3000). The extra cost is per-struct analysis work
  (symbol resolution) that grows with the total type count, not output volume.
- **kotlinc** (Kotlin/Native frontend) — the steepest phase: ≈N^1.7 on 1000→3000,
  and **super-linear in memory** too. At the default daemon heap it dies with
  `OutOfMemoryError: Java heap space` at N=3000 (FIR construction over the 201k-line
  file); the root `gradle.properties` now sets `kotlin.daemon.jvmargs=-Xmx16g`.
- **swift / link** — effectively `fixed_cost + O(N)`. Swift build includes the
  SwiftPM-plugin thunk regeneration (itself the super-linear generator) plus
  `swiftc` on the ~56 lines/struct thunk file.
- **run** — flat; dominated by process + cold dyld symbol-bind startup. The
  struct/`Inout` work is negligible (a warm re-run of the N=1000 binary is ~0.05 s).

**Conclusion.** The struct + `Inout<T>` pipeline is dominated by two **super-linear**
phases — jextract generation and (most of all) the Kotlin/Native frontend — which
are near-linear at small N but bend upward past N≈1000 (kotlinc ≈ N^1.7, gen ≈
N^1.4–1.5 at the top of the measured range). The linker and Swift build are ~linear
with large fixed costs, and runtime is constant-ish. (An even earlier run that put
gen at ~N^1.6 for *small* N was a heavily-loaded-machine artifact; the super-linear
behaviour reported here is at large N on an idle machine and is reproducible.)

> **N=10000 note.** At N=10000 the generator alone runs 10+ min and emits 670,020
> lines of Kotlin + ~560k lines of Swift thunks; the Swift build and Kotlin compile
> that follow are very long and may exhaust even the 16 GB Kotlin heap. This point
> was not completed in an automated pass — run it manually and expect it to be slow
> or heap-bound:
> `Samples/KotlinNativeStructStressApp/measure.sh 10000`
