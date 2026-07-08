// Minimal Swift library for testing Kotlin/Native cinterop bindings.
// Mirrors the KotlinFFMSampleApp source so the two modes can be compared
// for parity. Contains only primitive types supported by the generators.

import Swift

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

// MARK: - Top-level global variables

/// A read-write global integer: exercises getter + setter thunks.
nonisolated(unsafe) public var globalScore: Int = 0

/// A read-only computed property: exercises getter-only thunk.
public var appVersion: String { return "1.0" }

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
        print("[SWIFT] init count=\(start) self=\(String(unsafeBitCast(self, to: UInt.self), radix: 16))")
    }

    deinit {
        _counterDeinits += 1
        print("[SWIFT] deinit count=\(count) self=\(String(unsafeBitCast(self, to: UInt.self), radix: 16))")
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

/// A value type exercising the uniform box path for structs.
// public struct Point {
//     public var x: Int
//     public var y: Int
//
//     public init(x: Int, y: Int) {
//         self.x = x
//         self.y = y
//     }
//
//     public func sum() -> Int {
//         return x + y
//     }
//
//     public func translated(dx: Int, dy: Int) -> Point {
//         return Point(x: x + dx, y: y + dy)
//     }
// }

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
// public struct Holder {
//     public let counter: Counter
//
//     public init(counter: Counter) {
//         self.counter = counter
//     }
//
//     public func value() -> Int {
//         return counter.currentValue()
//     }
// }
