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
