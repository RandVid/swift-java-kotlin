// Minimal Swift library for testing Kotlin/Native cinterop bindings.
// Mirrors the KotlinFFMSampleApp source so the two modes can be compared
// for parity. Contains only primitive types supported by the generators.

public func helloWorld() {
  print("Hello from Swift!")
}

public func add(a: Int, b: Int) -> Int {
  return a + b
}

public func greet(name: String) -> String {
  return "Hello, \(name)!"
}

public func isPositive(value: Int) -> Bool {
  return value > 0
}

public func divide(a: Double, b: Double) -> Double {
  return a / b
}

public func printMessage(message: String) {
  print(message)
}

public func addInt8(a: Int8, b: Int8) -> Int8 {
  return a + b
}

public func addInt16(a: Int16, b: Int16) -> Int16 {
  return a + b
}

public func addInt64(a: Int64, b: Int64) -> Int64 {
  return a + b
}

public func addFloat(a: Float, b: Float) -> Float {
  return a + b
}

public func addUInt8(a: UInt8, b: UInt8) -> UInt8 {
  return a + b
}

public func addUInt16(a: UInt16, b: UInt16) -> UInt16 {
  return a + b
}

public func addUInt32(a: UInt32, b: UInt32) -> UInt32 {
  return a + b
}

public func addUInt64(a: UInt64, b: UInt64) -> UInt64 {
  return a + b
}

public func returnUByteArrayFirstElement(arr: [UInt8]) -> UInt8 {
    return arr[0]
}

public func returnUByteArray(a: UInt8, b: UInt8, c: UInt8) -> [UInt8] {
    return [a, b, c]
}

public func returnUByteArraysFirstElements(arr1: [UInt8], arr2: [UInt8]) -> [UInt8] {
    return [arr1[0], arr2[0]]
}

// Optional parameter functions
public func addIfPresent(a: Int, b: Int?) -> Int {
    return a + (b ?? 0)
}

public func sumOptionals(a: Int?, b: Int?) -> Int {
    return (a ?? 0) + (b ?? 0)
}

public func scaleIfPresent(value: Double, factor: Double?) -> Double {
    return value * (factor ?? 1.0)
}

public func absOptUByte(b: UInt8?) -> UInt8 {
    return b ?? 0
}

// Optional return functions
public func maybePositive(x: Int) -> Int? {
    return x > 0 ? x : nil
}

public func maybeDouble(x: Double) -> Double? {
    return x != 0.0 ? x : nil
}

public func maybeInt32(x: Int32) -> Int32? {
    return x != 0 ? x : nil
}

public func maybeUByte(x: UInt8) -> UInt8? {
    return x != 0 ? x : nil
}

// Optional parameter with optional return
public func doubleIfPresent(x: Int?) -> Int? {
    guard let x else { return nil }
    return x * 2
}

// Optional String parameters
public func greetIfPresent(name: String?) -> String {
    guard let name else { return "Hello, stranger!" }
    return "Hello, \(name)!"
}

// Optional String return
public func initials(fullName: String) -> String? {
    let parts = fullName.split(separator: " ").map(String.init)
    guard parts.count >= 2 else { return nil }
    return parts.map { String($0.prefix(1)) }.joined(separator: ".")
}

// Optional String param + optional String return
public func maybeUpper(s: String?) -> String? {
    return s?.uppercased()
}

// MARK: - Top-level global variables

/// A read-write global integer: exercises getter + setter thunks.
nonisolated(unsafe) public var globalScore: Int = 0

/// A read-only computed property: exercises getter-only thunk.
public var appVersion: String { return "1.0" }

/// Optional global: exercises the heap-pointer optional ABI.
nonisolated(unsafe) public var globalTag: Int? = nil

/// Array global: exercises the out-count ABI for globals.
nonisolated(unsafe) public var globalBytes: [UInt8] = []

// MARK: - Custom class / struct support

// Lifetime instrumentation so Kotlin/Native tests can assert that boxes are
// destroyed exactly once, never early, and never leaked. Single-threaded test
// use; `nonisolated(unsafe)` opts these globals out of strict-concurrency checks.
nonisolated(unsafe) private var _counterInits = 0
nonisolated(unsafe) private var _counterDeinits = 0

/// Number of `Counter` instances constructed so far.
public func counterInitCount() -> Int { _counterInits }
/// Number of `Counter` instances deinitialized (released) so far.
public func counterDeinitCount() -> Int { _counterDeinits }

/// A reference type exercising init, instance methods, a read/write property,
/// a static factory returning a custom type, and a method returning a custom type.
public class Counter {
    private var count: Int

    public init(start: Int) {
        self.count = start
        _counterInits += 1
    }

    deinit {
        _counterDeinits += 1
    }

    /// Returns `self` — exercises returning an *existing* object across the
    /// boundary (the +1 retain on the return path). Two wrappers then share one
    /// underlying Swift object.
    public func selfReference() -> Counter {
        return self
    }

    public func increment(by amount: Int) {
        count += amount
    }

    public func currentValue() -> Int {
        return count
    }

    public func describe() -> String {
        return "Counter(\(count))"
    }

    public var value: Int {
        get { count }
        set { count = newValue }
    }

    public static func starting(at start: Int) -> Counter {
        return Counter(start: start)
    }

    /// Returns a new Counter holding the sum — exercises a custom type as both
    /// a parameter and a return value of an instance method.
    public func plus(other: Counter) -> Counter {
        return Counter(start: count + other.count)
    }
}

extension Counter {
    public func sixseven() {
        count = 67
    }
}

/// A class exercising optional (`T?`) params and returns on methods and properties.
public class OptionalBox {
    private var storage: Int?

    public init(value: Int?) {
        self.storage = value
    }

    /// Optional read/write property.
    public var value: Int? {
        get { storage }
        set { storage = newValue }
    }

    /// Optional param.
    public func set(newValue: Int?) {
        storage = newValue
    }

    /// Optional return.
    public func get() -> Int? {
        return storage
    }

    /// Optional param + optional return.
    public func transform(by factor: Int?) -> Int? {
        guard let v = storage, let f = factor else { return nil }
        return v * f
    }

    /// Optional String return.
    public func describe() -> String? {
        return storage.map { "value=\($0)" }
    }

    /// Optional String param.
    public func parseAndSet(from s: String?) {
        storage = s.flatMap { Int($0) }
    }
}

/// A class dedicated to exercising [UInt8] array params/returns across all
/// member surfaces: constructor, instance methods, a read/write property,
/// and a static method.
public class ByteBuffer {
    private var storage: [UInt8]

    /// Constructor with array param.
    public init(bytes: [UInt8]) {
        self.storage = bytes
    }

    /// Read/write array property.
    public var bytes: [UInt8] {
        get { storage }
        set { storage = newValue }
    }

    /// Array param: append bytes to internal storage.
    public func append(bytes: [UInt8]) {
        storage.append(contentsOf: bytes)
    }

    /// Array return: snapshot of current contents.
    public func snapshot() -> [UInt8] {
        return storage
    }

    /// Array param + array return: shift each byte by storage length.
    public func transform(data: [UInt8]) -> [UInt8] {
        let shift = UInt8(storage.count & 0xFF)
        return data.map { UInt8(($0 &+ shift)) }
    }

    /// Static array return.
    public static func zeros(count: Int) -> [UInt8] {
        return [UInt8](repeating: 0, count: count)
    }
}

/// A value type exercising the uniform box path for structs.
public struct Point {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public func sum() -> Int {
        return x + y
    }

    public func translated(dx: Int, dy: Int) -> Point {
        return Point(x: x + dx, y: y + dy)
    }
}

/// Top-level function taking and returning a custom type.
public func combine(a: Counter, b: Counter) -> Counter {
    return Counter(start: a.currentValue() + b.currentValue())
}

// A persistent Swift-side strong reference, used to prove that an object stays
// alive once the host holds its box even after Swift drops its own reference.
nonisolated(unsafe) private var _swiftStrongRef: Counter? = nil

/// Creates a `Counter`, stores the only Swift-side strong reference in a global,
/// and also returns it to the host (which holds its own box). After this call the
/// object has two owners: `_swiftStrongRef` and the host's box.
public func retainCounterInSwift(start: Int) -> Counter {
    let c = Counter(start: start)
    _swiftStrongRef = c
    return c
}

/// Drops the Swift-side strong reference established by `retainCounterInSwift`,
/// leaving the host's box as the only remaining owner.
public func dropSwiftStrongRef() {
    _swiftStrongRef = nil
}

// A weak reference used to observe ARC deallocation without going through
// the deinit counter. Unlike counterDeinitCount(), a weak reference is nil'd
// by the runtime the instant the last strong reference drops — not when the
// deinit body runs — which makes it a sharper lifetime probe.
nonisolated(unsafe) private weak var _weakCounterRef: Counter? = nil

/// Store a weak reference to `counter`. The reference becomes nil as soon as
/// the last strong owner releases it (i.e. after the host calls close()).
public func storeWeakRef(to counter: Counter) {
    _weakCounterRef = counter
}

/// Returns true if the weak reference stored by `storeWeakRef` is still alive.
public func isWeakRefAlive() -> Bool {
    return _weakCounterRef != nil
}

/// A value type holding a *reference* member, so that destroying a `Holder` box
/// must release its `counter` — exercises the struct branch of the `_destroy`
/// thunk (`deinitialize` releasing reference-typed fields, not just freeing bytes).
public struct Holder {
    public let counter: Counter

    public init(counter: Counter) {
        self.counter = counter
    }

    public func value() -> Int {
        return counter.currentValue()
    }
}
