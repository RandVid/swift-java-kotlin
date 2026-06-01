//
//  KotlinNativeTopLevelFunctionsTests.swift
//  swift-java
//
//  Mirrors KotlinTopLevelFunctionsTests but for the `kotlinNative` mode, which
//  generates Kotlin/Native wrappers that call the Swift `@_cdecl` C thunks
//  directly (via cinterop) instead of delegating to a Java FFM class.
//
//  Functions use explicit argument labels so the expected thunk symbol names
//  (`swiftjava_<module>_<name>_<labels>`) are deterministic.
//
import JExtractSwiftLib
import Testing

@Suite
struct KotlinNativeTopLevelFunctionsTests {

  // MARK: - Int / Int32

  @Test
  func int_asParameter() throws {
    try assertOutput(
      input: "public func acceptInt(x: Int) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptInt(x: Long): Unit {
          swiftjava_SwiftModule_acceptInt_x(x)
        }
        """
      ]
    )
  }

  @Test
  func int32_asParameter() throws {
    try assertOutput(
      input: "public func acceptInt32(x: Int32) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptInt32(x: Int): Unit {
          swiftjava_SwiftModule_acceptInt32_x(x)
        }
        """
      ]
    )
  }

  @Test
  func int_asReturn() throws {
    try assertOutput(
      input: "public func returnInt() -> Int { 42 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnInt(): Long {
          return swiftjava_SwiftModule_returnInt()
        }
        """
      ]
    )
  }

  @Test
  func int_parameterAndReturn() throws {
    try assertOutput(
      input: "public func incrementInt(x: Int) -> Int { x + 1 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun incrementInt(x: Long): Long {
          return swiftjava_SwiftModule_incrementInt_x(x)
        }
        """
      ]
    )
  }

  @Test
  func int_multipleParameters() throws {
    try assertOutput(
      input: "public func addInts(a: Int, b: Int, c: Int) -> Int { a + b + c }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun addInts(a: Long, b: Long, c: Long): Long {
          return swiftjava_SwiftModule_addInts_a_b_c(a, b, c)
        }
        """
      ]
    )
  }

  // MARK: - Bool

  @Test
  func bool_asReturn() throws {
    try assertOutput(
      input: "public func isPositive(value: Int) -> Bool { value > 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun isPositive(value: Long): Boolean {
          return swiftjava_SwiftModule_isPositive_value(value)
        }
        """
      ]
    )
  }

  @Test
  func bool_parameterAndReturn() throws {
    try assertOutput(
      input: "public func negate(flag: Bool) -> Bool { !flag }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun negate(flag: Boolean): Boolean {
          return swiftjava_SwiftModule_negate_flag(flag)
        }
        """
      ]
    )
  }

  // MARK: - Double

  @Test
  func double_parameterAndReturn() throws {
    try assertOutput(
      input: "public func divide(a: Double, b: Double) -> Double { a / b }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun divide(a: Double, b: Double): Double {
          return swiftjava_SwiftModule_divide_a_b(a, b)
        }
        """
      ]
    )
  }

  // MARK: - String is not supported yet on Kotlin/Native (needs memScoped)

  @Test
  func string_asParameter_isSkipped() throws {
    try assertOutput(
      input: "public func printMessage(message: String) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        "// Skipped printMessage: String parameter not supported in kotlinNative mode"
      ]
    )
  }

  @Test
  func string_asReturn_isSkipped() throws {
    try assertOutput(
      input: "public func makeGreeting() -> String { \"hi\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "// Skipped makeGreeting: String return type not supported in kotlinNative mode"
      ]
    )
  }

  // MARK: - Void

  @Test
  func void_noParametersNoReturn() throws {
    try assertOutput(
      input: "public func helloWorld() {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun helloWorld(): Unit {
          swiftjava_SwiftModule_helloWorld()
        }
        """
      ]
    )
  }

  // MARK: - Mixed

  @Test
  func mixed_intBoolReturn() throws {
    try assertOutput(
      input: "public func check(count: Int, enabled: Bool) -> Bool { enabled && count > 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun check(count: Long, enabled: Boolean): Boolean {
          return swiftjava_SwiftModule_check_count_enabled(count, enabled)
        }
        """
      ]
    )
  }

  // MARK: - Unsupported types are skipped

  @Test
  func unsupported_arrayParameter_isSkipped() throws {
    try assertOutput(
      input: "public func sum(values: [Int]) -> Int { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "// Skipped sum: unsupported param type"
      ]
    )
  }

  @Test
  func unsupported_optionalReturn_isSkipped() throws {
    try assertOutput(
      input: "public func maybeInt() -> Int? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "// Skipped maybeInt: unsupported return type"
      ]
    )
  }
}
