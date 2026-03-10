//
//  KotlinTopLevelFunctionsTests.swift
//  swift-java
//
//  Created by Ilya Plisko on 20.02.26.
//
import JExtractSwiftLib
import Testing

@Suite
struct KotlinTopLevelFunctionsTests {

  // MARK: - Int/Int32 Tests

  @Test
  func int_asParameter() throws {
    let source = "public func acceptInt(_ x: Int) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun acceptInt(x: Long): Unit {
          SwiftModule.acceptInt(x)
        }
        """
      ]
    )
  }

  @Test
  func int32_asParameter() throws {
    let source = "public func acceptInt32(_ x: Int32) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun acceptInt32(x: Int): Unit {
          SwiftModule.acceptInt32(x)
        }
        """
      ]
    )
  }

  @Test
  func int_asReturn() throws {
    let source = "public func returnInt() -> Int { 42 }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun returnInt(): Long {
          return SwiftModule.returnInt()
        }
        """
      ]
    )
  }

  @Test
  func int32_asReturn() throws {
    let source = "public func returnInt32() -> Int32 { 42 }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun returnInt32(): Int {
          return SwiftModule.returnInt32()
        }
        """
      ]
    )
  }

  @Test
  func int_parameterAndReturn() throws {
    let source = "public func incrementInt(_ x: Int) -> Int { x + 1 }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun incrementInt(x: Long): Long {
          return SwiftModule.incrementInt(x)
        }
        """
      ]
    )
  }

  @Test
  func int32_parameterAndReturn() throws {
    let source = "public func incrementInt32(_ x: Int32) -> Int32 { x + 1 }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun incrementInt32(x: Int): Int {
          return SwiftModule.incrementInt32(x)
        }
        """
      ]
    )
  }

  @Test
  func int_multipleParameters() throws {
    let source = "public func addInts(_ a: Int, _ b: Int, _ c: Int) -> Int { a + b + c }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun addInts(a: Long, b: Long, c: Long): Long {
          return SwiftModule.addInts(a, b, c)
        }
        """
      ]
    )
  }

  @Test
  func intMixed_int32AndInt() throws {
    let source = "public func addMixed(_ a: Int32, _ b: Int) -> Int32 { a + Int32(b) }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun addMixed(a: Int, b: Long): Int {
          return SwiftModule.addMixed(a, b)
        }
        """
      ]
    )
  }

  // MARK: - Bool Tests

  @Test
  func bool_asParameter() throws {
    let source = "public func acceptBool(_ x: Bool) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun acceptBool(x: Boolean): Unit {
          SwiftModule.acceptBool(x)
        }
        """
      ]
    )
  }

  @Test
  func bool_asReturn() throws {
    let source = "public func returnBool() -> Bool { true }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun returnBool(): Boolean {
          return SwiftModule.returnBool()
        }
        """
      ]
    )
  }

  @Test
  func bool_parameterAndReturn() throws {
    let source = "public func negateBool(_ x: Bool) -> Bool { !x }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun negateBool(x: Boolean): Boolean {
          return SwiftModule.negateBool(x)
        }
        """
      ]
    )
  }

  @Test
  func bool_multipleParameters() throws {
    let source = "public func andBools(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool { a && b && c }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun andBools(a: Boolean, b: Boolean, c: Boolean): Boolean {
          return SwiftModule.andBools(a, b, c)
        }
        """
      ]
    )
  }

  // MARK: - Double Tests

  @Test
  func double_asParameter() throws {
    let source = "public func acceptDouble(_ x: Double) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun acceptDouble(x: Double): Unit {
          SwiftModule.acceptDouble(x)
        }
        """
      ]
    )
  }

  @Test
  func double_asReturn() throws {
    let source = "public func returnDouble() -> Double { 3.14 }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun returnDouble(): Double {
          return SwiftModule.returnDouble()
        }
        """
      ]
    )
  }

  @Test
  func double_parameterAndReturn() throws {
    let source = "public func doubleIt(_ x: Double) -> Double { x * 2.0 }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun doubleIt(x: Double): Double {
          return SwiftModule.doubleIt(x)
        }
        """
      ]
    )
  }

  @Test
  func double_multipleParameters() throws {
    let source = "public func multiplyDoubles(_ a: Double, _ b: Double, _ c: Double) -> Double { a * b * c }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun multiplyDoubles(a: Double, b: Double, c: Double): Double {
          return SwiftModule.multiplyDoubles(a, b, c)
        }
        """
      ]
    )
  }

  // MARK: - String Tests

  @Test
  func string_asParameter() throws {
    let source = "public func acceptString(_ s: String) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun acceptString(s: String): Unit {
          SwiftModule.acceptString(s)
        }
        """
      ]
    )
  }

  @Test
  func string_asReturn() throws {
    let source = "public func returnString() -> String { \"hello\" }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped returnString: String return type not supported in FFM mode
        """
      ]
    )
  }

  @Test
  func string_parameterAndReturn() throws {
    let source = "public func echoString(_ s: String) -> String { s }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped echoString: String return type not supported in FFM mode
        """
      ]
    )
  }

  @Test
  func string_multipleParameters() throws {
    let source = "public func concatStrings(_ a: String, _ b: String, _ c: String) -> String { a + b + c }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped concatStrings: String return type not supported in FFM mode
        """
      ]
    )
  }

  // MARK: - Void/Unit Tests

  @Test
  func void_noParametersNoReturn() throws {
    let source = "public func empty() {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun empty(): Unit {
          SwiftModule.empty()
        }
        """
      ]
    )
  }

  @Test
  func void_withParameterNoReturn() throws {
    let source = "public func logString(_ s: String) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun logString(s: String): Unit {
          SwiftModule.logString(s)
        }
        """
      ]
    )
  }

  @Test
  func void_multipleParametersNoReturn() throws {
    let source = "public func logMultiple(_ a: Int, _ b: String, _ c: Bool) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun logMultiple(a: Long, b: String, c: Boolean): Unit {
          SwiftModule.logMultiple(a, b, c)
        }
        """
      ]
    )
  }

  // MARK: - Mixed Type Combinations

  @Test
  func mixed_intBoolReturn() throws {
    let source = "public func compare(_ a: Int, _ b: Int) -> Bool { a > b }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun compare(a: Long, b: Long): Boolean {
          return SwiftModule.compare(a, b)
        }
        """
      ]
    )
  }

  @Test
  func mixed_stringIntReturn() throws {
    let source = "public func stringLength(_ s: String) -> Int { s.count }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun stringLength(s: String): Long {
          return SwiftModule.stringLength(s)
        }
        """
      ]
    )
  }

  @Test
  func mixed_boolStringReturn() throws {
    let source = "public func boolToString(_ b: Bool) -> String { b ? \"true\" : \"false\" }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped boolToString: String return type not supported in FFM mode
        """
      ]
    )
  }

  @Test
  func mixed_doubleIntReturn() throws {
    let source = "public func roundDouble(_ x: Double) -> Int { Int(x) }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun roundDouble(x: Double): Long {
          return SwiftModule.roundDouble(x)
        }
        """
      ]
    )
  }

  @Test
  func mixed_intDoubleReturn() throws {
    let source = "public func intToDouble(_ x: Int) -> Double { Double(x) }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun intToDouble(x: Long): Double {
          return SwiftModule.intToDouble(x)
        }
        """
      ]
    )
  }

  @Test
  func mixed_allPrimitivesAsParameters() throws {
    let source = "public func acceptAll(_ i: Int, _ b: Bool, _ d: Double, _ s: String) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun acceptAll(i: Long, b: Boolean, d: Double, s: String): Unit {
          SwiftModule.acceptAll(i, b, d, s)
        }
        """
      ]
    )
  }

  @Test
  func mixed_complexSignature() throws {
    let source = "public func complexFunc(_ x: Double, _ flag: Bool, _ count: Int32, _ label: String) -> Int { count }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun complexFunc(x: Double, flag: Boolean, count: Int, label: String): Long {
          return SwiftModule.complexFunc(x, flag, count, label)
        }
        """
      ]
    )
  }

  @Test
  func mixed_namedParameters() throws {
    let source = "public func scale(_ value: Double, by factor: Int) -> Double { value * Double(factor) }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun scale(value: Double, factor: Long): Double {
          return SwiftModule.scale(value, factor)
        }
        """
      ]
    )
  }

  // MARK: - Unsupported Types

  @Test
  func unsupported_arrayParameter() throws {
    let source = "public func acceptArray(_ arr: Array<Int32>) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped acceptArray: unsupported param type 'Array<Int32>'
        """
      ]
    )
  }

  @Test
  func unsupported_arrayReturn() throws {
    let source = "public func returnArray() -> Array<Int32> { [] }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped returnArray: unsupported return type 'Array<Int32>'
        """
      ]
    )
  }

  @Test
  func unsupported_optionalParameter() throws {
    let source = "public func acceptOptional(_ x: Int?) {}"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped acceptOptional: unsupported param type 'Int?'
        """
      ]
    )
  }

  @Test
  func unsupported_optionalReturn() throws {
    let source = "public func returnOptional() -> String? { nil }"
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        // Skipped returnOptional: unsupported return type 'String?'
        """
      ]
    )
  }

  @Test
  func unsupported_mixedValidAndInvalid() throws {
    let source = """
      public func validFunc(_ x: Int) -> Double { 42.0 }
      public func invalidFunc(_ arr: [Int]) -> Int { 0 }
      """
    try assertOutput(
      input: source,
      .kotlin,
      .java,
      expectedChunks: [
        """
        fun validFunc(x: Long): Double {
          return SwiftModule.validFunc(x)
        }
        """,
        """
        // Skipped invalidFunc: unsupported param type '[Int]'
        """
      ]
    )
  }
}
