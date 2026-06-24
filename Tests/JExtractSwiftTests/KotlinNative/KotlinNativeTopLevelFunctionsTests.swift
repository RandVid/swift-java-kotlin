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

  // MARK: - Int8 / Int16 / Int64 / Float

  @Test
  func int8_asParameter() throws {
    try assertOutput(
      input: "public func acceptInt8(x: Int8) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptInt8(x: Byte): Unit {
          swiftjava_SwiftModule_acceptInt8_x(x)
        }
        """
      ]
    )
  }

  @Test
  func int8_asReturn() throws {
    try assertOutput(
      input: "public func returnInt8() -> Int8 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnInt8(): Byte {
          return swiftjava_SwiftModule_returnInt8()
        }
        """
      ]
    )
  }

  @Test
  func int16_asParameter() throws {
    try assertOutput(
      input: "public func acceptInt16(x: Int16) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptInt16(x: Short): Unit {
          swiftjava_SwiftModule_acceptInt16_x(x)
        }
        """
      ]
    )
  }

  @Test
  func int16_asReturn() throws {
    try assertOutput(
      input: "public func returnInt16() -> Int16 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnInt16(): Short {
          return swiftjava_SwiftModule_returnInt16()
        }
        """
      ]
    )
  }

  @Test
  func int64_asParameter() throws {
    try assertOutput(
      input: "public func acceptInt64(x: Int64) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptInt64(x: Long): Unit {
          swiftjava_SwiftModule_acceptInt64_x(x)
        }
        """
      ]
    )
  }

  @Test
  func int64_asReturn() throws {
    try assertOutput(
      input: "public func returnInt64() -> Int64 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnInt64(): Long {
          return swiftjava_SwiftModule_returnInt64()
        }
        """
      ]
    )
  }

  @Test
  func float_asParameter() throws {
    try assertOutput(
      input: "public func acceptFloat(x: Float) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptFloat(x: Float): Unit {
          swiftjava_SwiftModule_acceptFloat_x(x)
        }
        """
      ]
    )
  }

  @Test
  func float_asReturn() throws {
    try assertOutput(
      input: "public func returnFloat() -> Float { 0.0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnFloat(): Float {
          return swiftjava_SwiftModule_returnFloat()
        }
        """
      ]
    )
  }

  @Test
  func float_parameterAndReturn() throws {
    try assertOutput(
      input: "public func halve(x: Float) -> Float { x / 2.0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun halve(x: Float): Float {
          return swiftjava_SwiftModule_halve_x(x)
        }
        """
      ]
    )
  }

  // MARK: - Unsigned integers

  @Test
  func uint8_asParameter() throws {
    try assertOutput(
      input: "public func acceptUInt8(x: UInt8) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptUInt8(x: UByte): Unit {
          swiftjava_SwiftModule_acceptUInt8_x(x)
        }
        """
      ]
    )
  }

  @Test
  func uint8_asReturn() throws {
    try assertOutput(
      input: "public func returnUInt8() -> UInt8 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnUInt8(): UByte {
          return swiftjava_SwiftModule_returnUInt8()
        }
        """
      ]
    )
  }

  @Test
  func uint16_asParameter() throws {
    try assertOutput(
      input: "public func acceptUInt16(x: UInt16) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptUInt16(x: UShort): Unit {
          swiftjava_SwiftModule_acceptUInt16_x(x)
        }
        """
      ]
    )
  }

  @Test
  func uint16_asReturn() throws {
    try assertOutput(
      input: "public func returnUInt16() -> UInt16 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnUInt16(): UShort {
          return swiftjava_SwiftModule_returnUInt16()
        }
        """
      ]
    )
  }

  @Test
  func uint32_asParameter() throws {
    try assertOutput(
      input: "public func acceptUInt32(x: UInt32) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptUInt32(x: UInt): Unit {
          swiftjava_SwiftModule_acceptUInt32_x(x)
        }
        """
      ]
    )
  }

  @Test
  func uint32_asReturn() throws {
    try assertOutput(
      input: "public func returnUInt32() -> UInt32 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnUInt32(): UInt {
          return swiftjava_SwiftModule_returnUInt32()
        }
        """
      ]
    )
  }

  @Test
  func uint64_asParameter() throws {
    try assertOutput(
      input: "public func acceptUInt64(x: UInt64) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptUInt64(x: ULong): Unit {
          swiftjava_SwiftModule_acceptUInt64_x(x)
        }
        """
      ]
    )
  }

  @Test
  func uint64_asReturn() throws {
    try assertOutput(
      input: "public func returnUInt64() -> UInt64 { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnUInt64(): ULong {
          return swiftjava_SwiftModule_returnUInt64()
        }
        """
      ]
    )
  }

  @Test
  func uint_asParameter() throws {
    try assertOutput(
      input: "public func acceptUInt(x: UInt) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptUInt(x: ULong): Unit {
          swiftjava_SwiftModule_acceptUInt_x(x)
        }
        """
      ]
    )
  }

  @Test
  func uint_asReturn() throws {
    try assertOutput(
      input: "public func returnUInt() -> UInt { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun returnUInt(): ULong {
          return swiftjava_SwiftModule_returnUInt()
        }
        """
      ]
    )
  }

  // MARK: - [UInt8] UByteArray parameters

  @Test
  func byteArray_asParameter_unitReturn() throws {
    try assertOutput(
      input: "public func processBytes(data: [UInt8]) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun processBytes(data: UByteArray): Unit {
          data.usePinned { pinned_data ->
            swiftjava_SwiftModule_processBytes_data(pinned_data.addressOf(0), data.size.toLong())
          }
        }
        """
      ]
    )
  }

  // MARK: - Optional String parameters

  @Test
  func optional_stringParam() throws {
    try assertOutput(
      input: "public func acceptOptString(s: String?) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptOptString(s: String?): Unit {
          swiftjava_SwiftModule_acceptOptString_s(s?.cstr)
        }
        """
      ]
    )
  }

  @Test
  func optional_stringParam_swiftThunk() throws {
    try assertOutput(
      input: "public func acceptOptString(s: String?) {}",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_acceptOptString_s")
        public func swiftjava_SwiftModule_acceptOptString_s(_ s: UnsafePointer<Int8>?) {
            acceptOptString(s: s.map { String(cString: $0) })
        }
        """
      ]
    )
  }

  @Test
  func optional_stringParam_withStringReturn() throws {
    try assertOutput(
      input: "public func greetOpt(name: String?) -> String { name ?? \"stranger\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun greetOpt(name: String?): String {
          val ptr = swiftjava_SwiftModule_greetOpt_name(name?.cstr) ?: return ""
          val result = ptr.toKString()
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func byteArray_asParameter_intReturn() throws {
    try assertOutput(
      input: "public func sumBytes(data: [UInt8]) -> Int { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun sumBytes(data: UByteArray): Long {
          return data.usePinned { pinned_data ->
            swiftjava_SwiftModule_sumBytes_data(pinned_data.addressOf(0), data.size.toLong())
          }
        }
        """
      ]
    )
  }

  @Test
  func byteArray_asParameter_stringReturn() throws {
    try assertOutput(
      input: "public func decodeBytes(data: [UInt8]) -> String { \"\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun decodeBytes(data: UByteArray): String {
          return data.usePinned { pinned_data ->
            val ptr = swiftjava_SwiftModule_decodeBytes_data(pinned_data.addressOf(0), data.size.toLong()) ?: return ""
            val result = ptr.toKString()
            free(ptr)
            result
          }
        }
        """
      ]
    )
  }

  @Test
  func byteArray_multipleArrayParameters() throws {
    try assertOutput(
      input: "public func combine(lhs: [UInt8], rhs: [UInt8]) -> Int { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun combine(lhs: UByteArray, rhs: UByteArray): Long {
          return lhs.usePinned { pinned_lhs ->
            rhs.usePinned { pinned_rhs ->
              swiftjava_SwiftModule_combine_lhs_rhs(pinned_lhs.addressOf(0), lhs.size.toLong(), pinned_rhs.addressOf(0), rhs.size.toLong())
            }
          }
        }
        """
      ]
    )
  }

  @Test
  func byteArray_mixedWithPrimitiveParameters() throws {
    try assertOutput(
      input: "public func writeBuffer(offset: Int, data: [UInt8]) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun writeBuffer(offset: Long, data: UByteArray): Unit {
          data.usePinned { pinned_data ->
            swiftjava_SwiftModule_writeBuffer_offset_data(offset, pinned_data.addressOf(0), data.size.toLong())
          }
        }
        """
      ]
    )
  }

  // MARK: - [UInt8] UByteArray return type

  @Test
  func byteArray_asReturn_noParams() throws {
    try assertOutput(
      input: "public func getData() -> [UInt8] { [] }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun getData(): UByteArray {
          memScoped {
            val countVar = alloc<LongVar>()
            val ptr = swiftjava_SwiftModule_getData(countVar.ptr) ?: return UByteArray(0)
            val count = countVar.value.convert<Int>()
            val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()
            free(ptr)
            return result
          }
        }
        """
      ]
    )
  }

  @Test
  func byteArray_asReturn_withPrimitiveParams() throws {
    try assertOutput(
      input: "public func repeatByte(byte: UInt8, count: Int) -> [UInt8] { [] }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun repeatByte(byte: UByte, count: Long): UByteArray {
          memScoped {
            val countVar = alloc<LongVar>()
            val ptr = swiftjava_SwiftModule_repeatByte_byte_count(byte, count, countVar.ptr) ?: return UByteArray(0)
            val count = countVar.value.convert<Int>()
            val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()
            free(ptr)
            return result
          }
        }
        """
      ]
    )
  }

  @Test
  func byteArray_asReturn_withArrayParam() throws {
    try assertOutput(
      input: "public func transform(input: [UInt8]) -> [UInt8] { input }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun transform(input: UByteArray): UByteArray {
          return input.usePinned { pinned_input ->
            memScoped {
              val countVar = alloc<LongVar>()
              val ptr = swiftjava_SwiftModule_transform_input(pinned_input.addressOf(0), input.size.toLong(), countVar.ptr) ?: return UByteArray(0)
              val count = countVar.value.convert<Int>()
              val result = ptr.reinterpret<ByteVar>().readBytes(count).asUByteArray()
              free(ptr)
              result
            }
          }
        }
        """
      ]
    )
  }

  @Test
  func byteArray_asReturn_freeIsImported() throws {
    try assertOutput(
      input: "public func getData() -> [UInt8] { [] }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import platform.posix.free"
      ]
    )
  }

  // MARK: - Swift thunk generation (.swift render kind)

  @Test
  func swiftThunk_primitiveReturn() throws {
    try assertOutput(
      input: "public func add(a: Int, b: Int) -> Int { 0 }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_add_a_b")
        public func swiftjava_SwiftModule_add_a_b(_ a: Int, _ b: Int) -> Int {
          return add(a: a, b: b)
        }
        """
      ]
    )
  }

  @Test
  func swiftThunk_byteArrayReturn() throws {
    try assertOutput(
      input: "public func getData() -> [UInt8] { [] }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_getData")
        public func swiftjava_SwiftModule_getData(_ result_count: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<UInt8>? {
            let _result: [UInt8] = getData()
            result_count.pointee = _result.count
            guard !_result.isEmpty else { return nil }
            let _ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: _result.count)
        """
      ]
    )
  }

  @Test
  func swiftThunk_byteArrayParam() throws {
    try assertOutput(
      input: "public func process(data: [UInt8]) -> UInt8 { 0 }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_process_data")
        public func swiftjava_SwiftModule_process_data(_ data_pointer: UnsafeRawPointer, _ data_count: Int) -> UInt8 {
        """
      ]
    )
  }

  // MARK: - Optional parameters (Phase 1)

  @Test
  func optional_intParam() throws {
    try assertOutput(
      input: "public func acceptOpt(x: Int?) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptOpt(x: Long?): Unit {
          swiftjava_SwiftModule_acceptOpt_x(x?.let { cValuesOf(it) })
        }
        """
      ]
    )
  }

  @Test
  func optional_intParam_swiftThunk() throws {
    try assertOutput(
      input: "public func acceptOpt(x: Int?) {}",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_acceptOpt_x")
        public func swiftjava_SwiftModule_acceptOpt_x(_ x: UnsafePointer<Int>?) {
        """
      ]
    )
  }

  @Test
  func optional_uByteParam() throws {
    try assertOutput(
      input: "public func acceptOptByte(b: UInt8?) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptOptByte(b: UByte?): Unit {
          swiftjava_SwiftModule_acceptOptByte_b(b?.let { ubyteArrayOf(it).refTo(0) })
        }
        """
      ]
    )
  }

  @Test
  func optional_boolParam() throws {
    try assertOutput(
      input: "public func acceptOptBool(flag: Bool?) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun acceptOptBool(flag: Boolean?): Unit {
          swiftjava_SwiftModule_acceptOptBool_flag(flag?.let { booleanArrayOf(it).refTo(0) })
        }
        """
      ]
    )
  }

  @Test
  func optional_intParam_withPrimitiveReturn() throws {
    try assertOutput(
      input: "public func withOpt(x: Int?, y: Int) -> Int { (x ?? 0) + y }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun withOpt(x: Long?, y: Long): Long {
          return swiftjava_SwiftModule_withOpt_x_y(x?.let { cValuesOf(it) }, y)
        }
        """
      ]
    )
  }

  @Test
  func optional_multipleOptionalParams() throws {
    try assertOutput(
      input: "public func maybeAdd(a: Int?, b: Int32?) -> Int { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun maybeAdd(a: Long?, b: Int?): Long {
          return swiftjava_SwiftModule_maybeAdd_a_b(a?.let { cValuesOf(it) }, b?.let { cValuesOf(it) })
        }
        """
      ]
    )
  }

  // MARK: - Optional returns (Phase 2)

  @Test
  func optional_intReturn() throws {
    try assertOutput(
      input: "public func maybeInt() -> Int? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun maybeInt(): Long? {
          val ptr = swiftjava_SwiftModule_maybeInt() ?: return null
          val result = ptr.pointed.value
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func optional_intReturn_importsFree() throws {
    try assertOutput(
      input: "public func maybeInt() -> Int? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import platform.posix.free"
      ]
    )
  }

  @Test
  func optional_doubleReturn() throws {
    try assertOutput(
      input: "public func maybeDouble() -> Double? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun maybeDouble(): Double? {
          val ptr = swiftjava_SwiftModule_maybeDouble() ?: return null
          val result = ptr.pointed.value
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func optional_int32Return() throws {
    try assertOutput(
      input: "public func maybeInt32() -> Int32? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun maybeInt32(): Int? {
          val ptr = swiftjava_SwiftModule_maybeInt32() ?: return null
          val result = ptr.pointed.value
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func optional_intReturn_swiftThunk() throws {
    try assertOutput(
      input: "public func maybeInt() -> Int? { nil }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_maybeInt")
        public func swiftjava_SwiftModule_maybeInt() -> UnsafeMutablePointer<Int>? {
            guard let _result: Int = maybeInt() else { return nil }
            let _ptr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            _ptr.initialize(to: _result)
            return _ptr
        }
        """
      ]
    )
  }

  @Test
  func optional_paramAndReturn() throws {
    try assertOutput(
      input: "public func doubleOpt(x: Int?) -> Int? { x }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun doubleOpt(x: Long?): Long? {
          val ptr = swiftjava_SwiftModule_doubleOpt_x(x?.let { cValuesOf(it) }) ?: return null
          val result = ptr.pointed.value
          free(ptr)
          return result
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
  func optional_stringParam_withStringReturn_swiftThunk() throws {
    try assertOutput(
      input: "public func greetOpt(name: String?) -> String { name ?? \"stranger\" }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_greetOpt_name")
        public func swiftjava_SwiftModule_greetOpt_name(_ name: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8> {
            return _swiftjava_stringToCString(greetOpt(name: name.map { String(cString: $0) }))
        }
        """
      ]
    )
  }

  // MARK: - Optional String returns

  @Test
  func optional_stringReturn() throws {
    try assertOutput(
      input: "public func maybeName() -> String? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun maybeName(): String? {
          val ptr = swiftjava_SwiftModule_maybeName() ?: return null
          val result = ptr.toKString()
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func optional_stringReturn_swiftThunk() throws {
    try assertOutput(
      input: "public func maybeName() -> String? { nil }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_maybeName")
        public func swiftjava_SwiftModule_maybeName() -> UnsafeMutablePointer<CChar>? {
            guard let _result: String = maybeName() else { return nil }
            return _swiftjava_stringToCString(_result)
        }
        """
      ]
    )
  }

  @Test
  func optional_stringReturn_importsFree() throws {
    try assertOutput(
      input: "public func maybeName() -> String? { nil }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import platform.posix.free"
      ]
    )
  }

  // MARK: - Optional String param + Optional String return combined

  @Test
  func optional_stringParamAndReturn() throws {
    try assertOutput(
      input: "public func maybeUpper(s: String?) -> String? { s?.uppercased() }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun maybeUpper(s: String?): String? {
          val ptr = swiftjava_SwiftModule_maybeUpper_s(s?.cstr) ?: return null
          val result = ptr.toKString()
          free(ptr)
          return result
        }
        """
      ]
    )
  }

  @Test
  func optional_stringParamAndReturn_swiftThunk() throws {
    try assertOutput(
      input: "public func maybeUpper(s: String?) -> String? { s?.uppercased() }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_maybeUpper_s")
        public func swiftjava_SwiftModule_maybeUpper_s(_ s: UnsafePointer<Int8>?) -> UnsafeMutablePointer<CChar>? {
            guard let _result: String = maybeUpper(s: s.map { String(cString: $0) }) else { return nil }
            return _swiftjava_stringToCString(_result)
        }
        """
      ]
    )
  }
}
