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

  // MARK: - String parameters (passed as null-terminated UTF-8 via .objcPtr())

  @Test
  func string_asParameter() throws {
    try assertOutput(
      input: "public func printMessage(message: String) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun printMessage(message: String): Unit {
          swiftjava_SwiftModule_printMessage_message(message.objcPtr())
        }
        """
      ]
    )
  }
  
  @Test(.disabled("Temporarily disabled"))
  func string_asParameter_swiftThunk() throws {
    try assertOutput(
      input: "public func printMessage(message: String) {}",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SimpleSwiftLib_printMessage_message")
        public func swiftjava_SimpleSwiftLib_printMessage_message(_ message: UnsafePointer<Int8>) {
          var message_converted = String(cString: message)
          printMessage(message: message_converted)
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
          return swiftjava_SwiftModule_countChars_s(s.objcPtr())
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
          swiftjava_SwiftModule_tag_label_value(label.objcPtr(), value)
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
          swiftjava_SwiftModule_log_prefix_message(prefix.objcPtr(), message.objcPtr())
        }
        """
      ]
    )
  }

  // MARK: - String return (thunk returns an autoreleased NSString box; wrapper reads it via interpretObjCPointer)

  @Test
  func string_asReturn() throws {
    try assertOutput(
      input: "public func makeGreeting() -> String { \"hi\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun makeGreeting(): String {
          return autoreleasepool { interpretObjCPointer<String>(swiftjava_SwiftModule_makeGreeting()) }
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
          return autoreleasepool { interpretObjCPointer<String>(swiftjava_SwiftModule_greet_name(name.objcPtr())) }
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
          return autoreleasepool { interpretObjCPointer<String>(swiftjava_SwiftModule_intToString_value(value)) }
        }
        """
      ]
    )
  }

  @Test
  func string_asReturn_usesInterpretObjCPointer() throws {
    // The String return is read back from the autoreleased NSString box with
    // interpretObjCPointer; no C-string free() is involved.
    try assertOutput(
      input: "public func makeGreeting() -> String { \"hi\" }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "return autoreleasepool { interpretObjCPointer<String>(swiftjava_SwiftModule_makeGreeting()) }"
      ],
      notExpectedChunks: [
        "import platform.posix.free",
        "toKString",
      ]
    )
  }

  @Test
  func string_asReturn_importsKotlinxCinterop() throws {
    // interpretObjCPointer / memScoped live in kotlinx.cinterop, still wildcard-imported.
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
  func string_primitiveOnly_doesNotImportPosixFree() throws {
    // platform.posix.free is no longer imported in any mode (strings use NSString).
    try assertOutput(
      input: "public func add(a: Int, b: Int) -> Int { a + b }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "fun add(a: Long, b: Long): Long {"
      ]
    )
  }

  // MARK: - @ImportedBridge externals (direct binding, no cinterop klib)

  @Test
  func importedBridge_primitiveExtern() throws {
    // Each Swift @_cdecl thunk is bound directly as an `external fun` annotated with
    // `@ImportedBridge`, replacing the cinterop `.def`/klib. Primitives map 1:1.
    try assertOutput(
      input: "public func addInts(a: Int32, b: Int32) -> Int32 { a + b }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        @ImportedBridge("swiftjava_SwiftModule_addInts_a_b")
        external fun swiftjava_SwiftModule_addInts_a_b(p0: Int, p1: Int): Int
        """
      ],
      notExpectedChunks: [
        "import com.example.swift.cinterop.*",
      ]
    )
  }

  @Test
  func importedBridge_stringExtern_usesNativePtr() throws {
    // String params/returns cross as NSString boxes, so the extern signature is all
    // `NativePtr` (a `void*`), not a C string.
    try assertOutput(
      input: "public func echo(message: String) -> String { message }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        @ImportedBridge("swiftjava_SwiftModule_echo_message")
        external fun swiftjava_SwiftModule_echo_message(p0: NativePtr): NativePtr
        """
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

  // MARK: - inout parameters via Inout<T>

  @Test
  func inout_voidReturn_kotlin() throws {
    try assertOutput(
      input: "public func addInPlace(value: inout Int, by amount: Int) { value += amount }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun addInPlace(value: Inout<Long>, amount: Long): Unit {
          memScoped {
            val value_cell = alloc<LongVar>()
            value_cell.value = value.unsafeValue
            swiftjava_SwiftModule_addInPlace_value_by(value_cell.ptr.rawValue, amount)
            value.unsafeValue = value_cell.value
          }
        }
        """
      ]
    )
  }

  @Test
  func inout_voidReturn_swiftThunk() throws {
    try assertOutput(
      input: "public func addInPlace(value: inout Int, by amount: Int) { value += amount }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_addInPlace_value_by")
        public func swiftjava_SwiftModule_addInPlace_value_by(_ value: UnsafeMutableRawPointer, _ amount: Int) {
            var _value = value.assumingMemoryBound(to: Int.self).pointee
            addInPlace(value: &_value, by: amount)
            value.assumingMemoryBound(to: Int.self).pointee = _value
        }
        """
      ]
    )
  }

  @Test(.disabled("Temporarily disabled"))
  func inoutString_kotlin() throws {
    try assertOutput(
      input: "public func replace(str: inout String, rep: String) { str = rep }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun replace(str: Inout<String>, rep: String): Unit {
          memScoped {
            val str_cell = alloc<CPointerVar<ByteVar>>()
            str_cell.value = str.unsafeValue.objcPtr()
            swiftjava_SwiftModule_replace_str_rep(str_cell.ptr.rawValue, rep.objcPtr())
            str.unsafeValue = str_cell.value
          }
        }
        """
      ]
    )
  }
  
  @Test(.disabled("Temporarily disabled"))
  func inoutString_swiftThunk() throws {
    try assertOutput(
      input: "public func replace(str: inout String, rep: String) { str = rep }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_replace_str_rep")
        public func swiftjava_SwiftModule_replace_str_rep(_ value: UnsafePointer<Int8>, _ rep: UnsafePointer<Int8>) {
            var _value = value.assumingMemoryBound(to: UnsafePointer<Int8>.self).pointee
            replace(str: String(cString: _value), rep: String(cString: rep))
            value.assumingMemoryBound(to: UnsafePointer<Int8>.self).pointee.pointee = _value
        }
        """
      ]
    )
  }

  @Test
  func inout_importsInout() throws {
    try assertOutput(
      input: "public func addInPlace(value: inout Int, by amount: Int) { value += amount }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import org.swift.swiftkit.kn.Inout"
      ]
    )
  }

  @Test
  func inout_primitiveReturn_kotlin() throws {
    // A non-Void return threads through `return memScoped { … ; _result }`.
    try assertOutput(
      input: "public func bump(_ x: inout Int32) -> Bool { x += 1; return true }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun bump(x: Inout<Int>): Boolean {
          return memScoped {
            val x_cell = alloc<IntVar>()
            x_cell.value = x.unsafeValue
            val _result = swiftjava_SwiftModule_bump__(x_cell.ptr.rawValue)
            x.unsafeValue = x_cell.value
            _result
          }
        }
        """
      ]
    )
  }

  @Test
  func inout_primitiveReturn_swiftThunk() throws {
    try assertOutput(
      input: "public func bump(_ x: inout Int32) -> Bool { x += 1; return true }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_bump__")
        public func swiftjava_SwiftModule_bump__(_ x: UnsafeMutableRawPointer) -> Bool {
            var _x = x.assumingMemoryBound(to: Int32.self).pointee
            let _result = bump(&_x)
            x.assumingMemoryBound(to: Int32.self).pointee = _x
            return _result
        }
        """
      ]
    )
  }

  @Test
  func inout_multipleParams_kotlin() throws {
    // Two inout scalars → two cells, both written back.
    try assertOutput(
      input: "public func swapAdd(a: inout Int, b: inout Int) { let t = a; a = b; b = t }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun swapAdd(a: Inout<Long>, b: Inout<Long>): Unit {
          memScoped {
            val a_cell = alloc<LongVar>()
            a_cell.value = a.unsafeValue
            val b_cell = alloc<LongVar>()
            b_cell.value = b.unsafeValue
            swiftjava_SwiftModule_swapAdd_a_b(a_cell.ptr.rawValue, b_cell.ptr.rawValue)
            a.unsafeValue = a_cell.value
            b.unsafeValue = b_cell.value
          }
        }
        """
      ]
    )
  }

  @Test
  func inout_customTypeParam_kotlin() throws {
    // inout of a custom type surfaces as `Inout<Point>`; the wrapper seeds a
    // box-pointer cell from the held value and rewraps the (re-boxed) result.
    try assertOutput(
      input: """
        public struct Point { public init() {} }
        public func move(p: inout Point) {}
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun move(p: Inout<Point>): Unit {
          memScoped {
            val p_cell = alloc<COpaquePointerVar>()
            p_cell.value = interpretCPointer<CPointed>(p.unsafeValue.__ptr())
            swiftjava_SwiftModule_move_p(p_cell.ptr.rawValue)
            p.unsafeValue = Point(wrapSwiftObject { p_cell.value!!.rawValue })
          }
        }
        """
      ]
    )
  }

  @Test
  func inout_customTypeParam_swiftThunk() throws {
    try assertOutput(
      input: """
        public struct Point { public init() {} }
        public func move(p: inout Point) {}
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_move_p")
        public func swiftjava_SwiftModule_move_p(_ p: UnsafeMutableRawPointer) {
            let p_box = p.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _p = Unmanaged<AnyObject>.fromOpaque(p_box).takeUnretainedValue() as! Point
            move(p: &_p)
            p.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_p as AnyObject).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func inout_customTypeParamAndReturn_kotlin() throws {
    // A custom-type return rides the freed return slot as an opaque box; the wrapper
    // re-wraps it while still writing the `inout` param back.
    try assertOutput(
      input: """
        public struct Point { public init() {} }
        public func replace(p: inout Point) -> Point { let old = p; p = Point(); return old }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun replace(p: Inout<Point>): Point {
          return memScoped {
            val p_cell = alloc<COpaquePointerVar>()
            p_cell.value = interpretCPointer<CPointed>(p.unsafeValue.__ptr())
            val _result = Point(wrapSwiftObject { swiftjava_SwiftModule_replace_p(p_cell.ptr.rawValue) })
            p.unsafeValue = Point(wrapSwiftObject { p_cell.value!!.rawValue })
            _result
          }
        }
        """
      ]
    )
  }

  @Test
  func inout_customTypeParamAndReturn_swiftThunk() throws {
    try assertOutput(
      input: """
        public struct Point { public init() {} }
        public func replace(p: inout Point) -> Point { let old = p; p = Point(); return old }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_replace_p")
        public func swiftjava_SwiftModule_replace_p(_ p: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
            let p_box = p.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _p = Unmanaged<AnyObject>.fromOpaque(p_box).takeUnretainedValue() as! Point
            let _result = replace(p: &_p)
            p.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_p as AnyObject).autorelease().toOpaque()
            return Unmanaged<AnyObject>.passRetained(_result as AnyObject).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  // MARK: - Top-level global variables

  @Test
  func globalVar_readWrite_kotlin() throws {
    try assertOutput(
      input: "public var counter: Int = 0",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        var counter: Long
            get() {
                return swiftjava_SwiftModule_counter_kn_get()
            }
            set(value) {
                swiftjava_SwiftModule_counter_kn_set(value)
            }
        """
      ]
    )
  }

  @Test
  func globalVar_readOnly_kotlin() throws {
    try assertOutput(
      input: "public var pi: Double { return 3.14159 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        val pi: Double
            get() {
                return swiftjava_SwiftModule_pi_kn_get()
            }
        """
      ]
    )
  }

  @Test
  func globalVar_string_kotlin() throws {
    try assertOutput(
      input: "public var greeting: String = \"hello\"",
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        var greeting: String
            get() {
                return autoreleasepool { interpretObjCPointer<String>(swiftjava_SwiftModule_greeting_kn_get()) }
            }
            set(value) {
                swiftjava_SwiftModule_greeting_kn_set(value.objcPtr())
            }
        """
      ]
    )
  }

  @Test
  func globalVar_customObject_kotlin() throws {
    try assertOutput(
      input: """
        public class Box { public init() {} }
        public var shared: Box = Box()
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        var shared: Box
            get() {
                return Box(wrapSwiftObject { swiftjava_SwiftModule_shared_kn_get() })
            }
            set(value) {
                swiftjava_SwiftModule_shared_kn_set(value.__ptr())
            }
        """
      ]
    )
  }

  @Test
  func globalVar_readWrite_swiftThunk() throws {
    try assertOutput(
      input: "public var counter: Int = 0",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_counter_kn_get")
        """,
        """
        @_cdecl("swiftjava_SwiftModule_counter_kn_set")
        """
      ]
    )
  }
}
