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
