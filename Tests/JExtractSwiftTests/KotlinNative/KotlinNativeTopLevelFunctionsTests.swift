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

  @Test
  func int32_asReturn() throws {
    try assertOutput(
      input: "public func returnInt32() -> Int32 { 42 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnInt32(): Int {
          return swiftjava_SwiftModule_returnInt32()
        }
        """
      ]
    )
  }

  @Test
  func intMixed_int32AndInt() throws {
    try assertOutput(
      input: "public func addMixed(a: Int32, b: Int) -> Int32 { a + Int32(b) }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun addMixed(a: Int, b: Long): Int {
          return swiftjava_SwiftModule_addMixed_a_b(a, b)
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

  // MARK: - String parameters (passed as null-terminated UTF-8 via .cstr)

  @Test
  func string_asParameter() throws {
    try assertOutput(
      input: "public func printMessage(message: String) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun printMessage(message: String): Unit {
          swiftjava_SwiftModule_printMessage_message(message.cstr)
        }
        """
      ]
    )
  }

  @Test
  func string_parameterWithPrimitiveReturn() throws {
    try assertOutput(
      input: "public func countChars(s: String) -> Int32 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun countChars(s: String): Int {
          return swiftjava_SwiftModule_countChars_s(s.cstr)
        }
        """
      ]
    )
  }

  @Test
  func string_mixedWithPrimitiveParameters() throws {
    try assertOutput(
      input: "public func tag(label: String, value: Int) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun tag(label: String, value: Long): Unit {
          swiftjava_SwiftModule_tag_label_value(label.cstr, value)
        }
        """
      ]
    )
  }

  @Test
  func string_multipleStringParameters() throws {
    try assertOutput(
      input: "public func log(prefix: String, message: String) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun log(prefix: String, message: String): Unit {
          swiftjava_SwiftModule_log_prefix_message(prefix.cstr, message.cstr)
        }
        """
      ]
    )
  }

  // MARK: - String return (thunk returns heap-allocated char*; wrapper copies then frees)

  @Test
  func string_asReturn() throws {
    try assertOutput(
      input: "public func makeGreeting() -> String { \"hi\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun makeGreeting(): String {
          val ptr = swiftjava_SwiftModule_makeGreeting() ?: return ""
          val result = ptr.toKString()
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func string_asReturn_withStringParam() throws {
    try assertOutput(
      input: "public func greet(name: String) -> String { \"Hello, \" + name }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun greet(name: String): String {
          val ptr = swiftjava_SwiftModule_greet_name(name.cstr) ?: return ""
          val result = ptr.toKString()
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func string_asReturn_withPrimitiveParam() throws {
    try assertOutput(
      input: "public func intToString(value: Int) -> String { String(value) }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun intToString(value: Long): String {
          val ptr = swiftjava_SwiftModule_intToString_value(value) ?: return ""
          val result = ptr.toKString()
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func string_asReturn_importsFree() throws {
    try assertOutput(
      input: "public func makeGreeting() -> String { \"hi\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import platform.posix.free"
      ]
    )
  }

  @Test
  func string_asReturn_importsToKString() throws {
    // toKString lives in kotlinx.cinterop which is wildcard-imported.
    try assertOutput(
      input: "public func makeGreeting() -> String { \"hi\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import kotlinx.cinterop.*"
      ]
    )
  }

  @Test
  func string_primitiveOnly_doesNotImportFree() throws {
    // When no function returns String, platform.posix.free must not be imported.
    try assertOutput(
      input: "public func add(a: Int, b: Int) -> Int { a + b }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "fun add(a: Long, b: Long): Long {"
      ],
      notExpectedChunks: [
        "import platform.posix.free"
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
        "// Skipped sum: unsupported param type '[Int]'"
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
