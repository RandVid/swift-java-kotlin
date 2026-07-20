//
//  KotlinNativeClassTests.swift
//  swift-java
//
//  Tests for `kotlinNative` custom class/struct support: wrapper classes over a
//  Swift-allocated box (Option B), constructors, instance & static methods,
//  property get/set, and custom types as parameters / return types.
//
//  Functions use explicit argument labels so the expected thunk symbol names
//  (`swiftjava_<module>_<Type>_<member>_<labels>`) are deterministic.
//
import JExtractSwiftLib
import Testing

@Suite
struct KotlinNativeClassTests {

  // MARK: - Wrapper skeleton

  @Test
  func wrapperClassSkeleton() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init(start: Int) {}
          public func increment(by: Int) {}
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        @OptIn(ExperimentalNativeApi::class)
        class Counter internal constructor(private val __obj: NSObject) {
          internal fun __ptr(): NativePtr = __obj.objcPtr()
        """
      ]
    )
  }

  @Test
  func swiftHandleImportedFromSwiftKitKN() throws {
    try assertOutput(
      input: "public class Counter { public init() {} }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "import org.swift.swiftkit.kn.SwiftHandle"
      ],
      notExpectedChunks: [
        "internal class SwiftHandle"
      ]
    )
  }

  // MARK: - Constructor

  @Test
  func constructor_kotlin() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init(start: Int) {}
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        constructor(start: Long) : this(wrapSwiftObject { swiftjava_SwiftModule_Counter_init_start(start) })
        """
      ]
    )
  }

  @Test
  func constructor_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init(start: Int) {}
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Counter_init_start")
        public func swiftjava_SwiftModule_Counter_init_start(_ start: Int) -> UnsafeMutableRawPointer {
            let _result = Counter(start: start) as AnyObject
            return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  // MARK: - Destroy thunk

  @Test
  func destroyThunk_swift() throws {
    try assertOutput(
      input: "public class Counter { public init() {} }",
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Counter_destroy")
        public func swiftjava_SwiftModule_Counter_destroy(_ pointer: UnsafeMutableRawPointer) {
            Unmanaged<AnyObject>.fromOpaque(pointer).release()
        }
        """
      ]
    )
  }

  // MARK: - Instance method

  @Test
  func instanceMethod_voidReturn_kotlin() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public func increment(by: Int) {}
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun increment(by: Long): Unit {
          swiftjava_SwiftModule_Counter_increment_by(by, __ptr())
        }
        """
      ]
    )
  }

  @Test
  func instanceMethod_primitiveReturn_kotlin() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public func currentValue() -> Int { 0 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun currentValue(): Long {
          return swiftjava_SwiftModule_Counter_currentValue(__ptr())
        }
        """
      ]
    )
  }

  @Test
  func instanceMethod_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public func add(x: Int) -> Int { x }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Counter_add_x")
        public func swiftjava_SwiftModule_Counter_add_x(_ x: Int, _ self: UnsafeRawPointer) -> Int {
          return (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Counter).add(x: x)
        }
        """
      ]
    )
  }

  @Test
  func instanceMethod_stringReturn_kotlin() throws {
    try assertOutput(
      input: """
        public class Greeter {
          public init() {}
          public func greet(name: String) -> String { name }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun greet(name: String): String {
          return autoreleasepool { interpretObjCPointer<String>(swiftjava_SwiftModule_Greeter_greet_name(name.objcPtr(), __ptr())) }
        }
        """
      ]
    )
  }

  // MARK: - Static method

  @Test
  func staticMethod_kotlin() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public static func zero() -> Int { 0 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        companion object {
          fun zero(): Long {
            return swiftjava_SwiftModule_Counter_zero()
          }
        }
        """
      ]
    )
  }

  @Test
  func staticMethod_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public static func zero() -> Int { 0 }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Counter_zero")
        public func swiftjava_SwiftModule_Counter_zero() -> Int {
          return Counter.zero()
        }
        """
      ]
    )
  }

  // MARK: - Properties

  @Test
  func property_getterAndSetter_kotlin() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public var value: Int = 0
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        var value: Long
          get() {
            return swiftjava_SwiftModule_Counter_value_kn_get(__ptr())
          }
          set(value) {
            swiftjava_SwiftModule_Counter_value_kn_set(value, __ptr())
          }
        """
      ]
    )
  }

  @Test
  func property_getterOnly_kotlin() throws {
    try assertOutput(
      input: """
        public class Counter {
          public init() {}
          public var value: Int { 0 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        val value: Long
          get() {
            return swiftjava_SwiftModule_Counter_value_kn_get(__ptr())
          }
        """
      ],
      notExpectedChunks: [
        """
          set
        """
      ]
    )
  }

  @Test
  func const_property_getterOnly_kotlin() throws {
      try assertOutput(
        input: """
          public class Counter {
            public init() {}
            public let value: Int = 5
          }
          """,
        .kotlinNative,
        .java,
        expectedChunks: [
          """
          val value: Long
            get() {
              return swiftjava_SwiftModule_Counter_value_kn_get(__ptr())
            }
          """
        ],
        notExpectedChunks: [
          """
            set
          """
        ]
      )
    }

  // MARK: - Struct (two-class value-semantics model: immutable + Mutable)

  @Test
  func struct_valueClass_kotlin() throws {
    // A struct emits a single `SwiftCopyable` value class with getters, a non-mutating
    // method, and an overridden `copy()`. Mutating operations are `Inout<…>` extensions.
    try assertOutput(
      input: """
        public struct Point {
          public init(x: Int, y: Int) {}
          public func sum() -> Int { 0 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        "class Point internal constructor(val obj: NSObject) : SwiftCopyable {",
        "internal fun __ptr(): NativePtr = obj.objcPtr()",
        """
        fun sum(): Long {
          return swiftjava_SwiftModule_Point_sum(__ptr())
        }
        """,
        "override fun copy(): Point = Point(wrapSwiftObject { swiftjava_SwiftModule_Point_copy(__ptr()) })",
      ],
      notExpectedChunks: [
        "class MutablePoint",
        "unsafeAsMutable",
        "mutatingCopy",
      ]
    )
  }

  @Test
  func struct_settablePropertyInoutExtension_kotlin() throws {
    // A settable stored `var` becomes an `Inout<Point>.x` extension property: it
    // reads the held value and writes by calling the setter thunk (which returns the
    // re-boxed value) and storing it back.
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        var Inout<Point>.x: Long
          get() = unsafeValue.x
          set(value) {
            memScoped {
              val self_slot = alloc<COpaquePointerVar>()
              self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
              swiftjava_SwiftModule_Point_x_kn_set(value, self_slot.ptr.rawValue)
              unsafeValue = Point(wrapSwiftObject { self_slot.value!!.rawValue })
            }
          }
        """,
      ]
    )
  }

  @Test
  func struct_immutableClassPropertyIsReadOnly_kotlin() throws {
    // The immutable class exposes the stored property as a read-only `val`.
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        val x: Long
          get() {
            return swiftjava_SwiftModule_Point_x_kn_get(__ptr())
          }
        """
      ]
    )
  }

  @Test
  func struct_initThunk_swift() throws {
    try assertOutput(
      input: """
        public struct Point {
          public init(x: Int, y: Int) {}
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        public func swiftjava_SwiftModule_Point_init_x_y(_ x: Int, _ y: Int) -> UnsafeMutableRawPointer {
            let _result = Point(x: x, y: y) as AnyObject
            return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  // MARK: - Struct value semantics: re-box + `obj` swap + copy thunks
  //
  // A struct is boxed by value in a frozen `__SwiftValue`. Setters and `mutating`
  // methods live on the Mutable view; their thunk raises `self`, mutates a local,
  // and returns a freshly re-boxed value. The Mutable wrapper (a normal class with
  // `var obj`) swaps `obj` to that new box, so the mutation persists on the
  // instance. `copy()` boxes a fresh independent value.

  @Test
  func struct_setterThunk_swap_swift() throws {
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Point_x_kn_set")
        public func swiftjava_SwiftModule_Point_x_kn_set(_ newValue: Int, _ self: UnsafeMutableRawPointer) {
            let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Point
            _self.x = newValue
            self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func struct_mutatingMethod_inoutExtension_kotlin() throws {
    // A `mutating` method is emitted as an `Inout<Point>` extension: it calls the
    // thunk (which returns the re-boxed value) and stores it back into the holder.
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public mutating func bump() { x += 1 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun Inout<Point>.bump() {
          memScoped {
            val self_slot = alloc<COpaquePointerVar>()
            self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
            swiftjava_SwiftModule_Point_bump(self_slot.ptr.rawValue)
            unsafeValue = Point(wrapSwiftObject { self_slot.value!!.rawValue })
          }
        }
        """
      ]
    )
  }

  @Test
  func struct_mutatingMethod_swap_swift() throws {
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public mutating func bump() { x += 1 }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Point_bump")
        public func swiftjava_SwiftModule_Point_bump(_ self: UnsafeMutableRawPointer) {
            let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Point
            _self.bump()
            self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func struct_customTypeField_connectedInoutAndMutate_kotlin() throws {
    // A settable custom-type field gets two mutation extensions on `Inout<Rect>`:
    //  - a *connected* `Inout<Point>` getter (nested `rect.topLeft.x = …` writes
    //    back through the parent), and
    //  - a scoped `mutateTopLeft { … }` that batches edits into one write-back.
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
        }
        public struct Rect {
          public var topLeft: Point
          public init(topLeft: Point) { self.topLeft = topLeft }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        val Inout<Rect>.topLeft: Inout<Point>
          get() = Inout(unsafeValue.topLeft) { newValue ->
            memScoped {
              val self_slot = alloc<COpaquePointerVar>()
              self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
              swiftjava_SwiftModule_Rect_topLeft_kn_set(newValue.__ptr(), self_slot.ptr.rawValue)
              unsafeValue = Rect(wrapSwiftObject { self_slot.value!!.rawValue })
            }
          }
        """,
        """
        fun Inout<Rect>.mutateTopLeft(block: Inout<Point>.() -> Unit) {
          val field = Inout(unsafeValue.topLeft)
          field.block()
          memScoped {
            val self_slot = alloc<COpaquePointerVar>()
            self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
            swiftjava_SwiftModule_Rect_topLeft_kn_set(field.unsafeValue.__ptr(), self_slot.ptr.rawValue)
            unsafeValue = Rect(wrapSwiftObject { self_slot.value!!.rawValue })
          }
        }
        """,
      ]
    )
  }

  @Test
  func struct_copyThunk_swift() throws {
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Point_copy")
        public func swiftjava_SwiftModule_Point_copy(_ self: UnsafeRawPointer) -> UnsafeMutableRawPointer {
            let _result = (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Point) as AnyObject
            return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func struct_nonMutatingMethod_isEmitted_swiftThunk() throws {
    // A non-mutating method reads an immutable copy raised from the box (no swap).
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public func peek() -> Int { x }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Point_peek")
        public func swiftjava_SwiftModule_Point_peek(_ self: UnsafeRawPointer) -> Int {
          return (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Point).peek()
        }
        """
      ]
    )
  }

  // MARK: - Struct mutations unlocked by the box-cell `self` (return slot is free)

  @Test
  func struct_nonVoidMutatingMethod_kotlin() throws {
    // With `self` carried by the box cell, a `mutating` method's return slot is free
    // for its own (scalar) result, so non-`Void` mutating methods are supported.
    try assertOutput(
      input: """
        public struct Counter {
          public var n: Int
          public init(n: Int) { self.n = n }
          public mutating func next() -> Int { n += 1; return n }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun Inout<Counter>.next(): Long {
          return memScoped {
            val self_slot = alloc<COpaquePointerVar>()
            self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
            val _result = swiftjava_SwiftModule_Counter_next(self_slot.ptr.rawValue)
            unsafeValue = Counter(wrapSwiftObject { self_slot.value!!.rawValue })
            _result
          }
        }
        """
      ]
    )
  }

  @Test
  func struct_nonVoidMutatingMethod_swiftThunk() throws {
    try assertOutput(
      input: """
        public struct Counter {
          public var n: Int
          public init(n: Int) { self.n = n }
          public mutating func next() -> Int { n += 1; return n }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Counter_next")
        public func swiftjava_SwiftModule_Counter_next(_ self: UnsafeMutableRawPointer) -> Int {
            let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Counter
            let _result = _self.next()
            self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
            return _result
        }
        """
      ]
    )
  }

  @Test
  func struct_mutatingMethodWithInoutParam_kotlin() throws {
    // A `mutating` method that also takes an `inout` param: both `self` and the
    // param ride box/scalar cells and are written back.
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public mutating func adjust(delta: inout Int) { x += delta; delta = x }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun Inout<Point>.adjust(delta: Inout<Long>) {
          memScoped {
            val delta_cell = alloc<LongVar>()
            delta_cell.value = delta.unsafeValue
            val self_slot = alloc<COpaquePointerVar>()
            self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
            swiftjava_SwiftModule_Point_adjust_delta(delta_cell.ptr.rawValue, self_slot.ptr.rawValue)
            delta.unsafeValue = delta_cell.value
            unsafeValue = Point(wrapSwiftObject { self_slot.value!!.rawValue })
          }
        }
        """
      ]
    )
  }

  @Test
  func struct_mutatingMethodWithInoutParam_swiftThunk() throws {
    try assertOutput(
      input: """
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public mutating func adjust(delta: inout Int) { x += delta; delta = x }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Point_adjust_delta")
        public func swiftjava_SwiftModule_Point_adjust_delta(_ delta: UnsafeMutableRawPointer, _ self: UnsafeMutableRawPointer) {
            var _delta = delta.assumingMemoryBound(to: Int.self).pointee
            let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Point
            _self.adjust(delta: &_delta)
            delta.assumingMemoryBound(to: Int.self).pointee = _delta
            self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func struct_mutatingMethodReturningCustomType_kotlin() throws {
    // The freed return slot also carries a custom-type result: the thunk hands back
    // an opaque box and the wrapper re-wraps it (`Token(wrapSwiftObject { … })`),
    // independently of the `self` write-back.
    try assertOutput(
      input: """
        public struct Token { public init() {} }
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public mutating func advance() -> Token { x += 1; return Token() }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun Inout<Point>.advance(): Token {
          return memScoped {
            val self_slot = alloc<COpaquePointerVar>()
            self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
            val _result = Token(wrapSwiftObject { swiftjava_SwiftModule_Point_advance(self_slot.ptr.rawValue) })
            unsafeValue = Point(wrapSwiftObject { self_slot.value!!.rawValue })
            _result
          }
        }
        """
      ]
    )
  }

  @Test
  func struct_mutatingMethodReturningCustomType_swiftThunk() throws {
    try assertOutput(
      input: """
        public struct Token { public init() {} }
        public struct Point {
          public var x: Int
          public init(x: Int) { self.x = x }
          public mutating func advance() -> Token { x += 1; return Token() }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Point_advance")
        public func swiftjava_SwiftModule_Point_advance(_ self: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
            let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! Point
            let _result = _self.advance()
            self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
            return Unmanaged<AnyObject>.passRetained(_result as AnyObject).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func class_settableStoredProperty_mutatesInPlace_kotlin() throws {
    // Contrast: a class has reference semantics — the setter mutates through the
    // box pointer directly (`__ptr()`), no re-box/swap, and `__obj` stays `val`.
    try assertOutput(
      input: """
        public class Point {
          public var x: Int
          public init(x: Int) { self.x = x }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        "class Point internal constructor(private val __obj: NSObject) {",
        """
        set(value) {
            swiftjava_SwiftModule_Point_x_kn_set(value, __ptr())
          }
        """
      ]
    )
  }

  // MARK: - Custom type as parameter / return

  @Test
  func customTypeAsReturn_topLevel_kotlin() throws {
    try assertOutput(
      input: """
        public class Box { public init() {} }
        public func makeBox() -> Box { Box() }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun makeBox(): Box {
          return Box(wrapSwiftObject { swiftjava_SwiftModule_makeBox() })
        }
        """
      ]
    )
  }

  @Test
  func customTypeAsReturn_topLevel_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Box { public init() {} }
        public func makeBox() -> Box { Box() }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_makeBox")
        public func swiftjava_SwiftModule_makeBox() -> UnsafeMutableRawPointer {
            let _result = makeBox() as AnyObject
            return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func customTypeAsParameter_topLevel_kotlin() throws {
    try assertOutput(
      input: """
        public class Box { public init() {} public func get() -> Int { 0 } }
        public func useBox(box: Box) -> Int { box.get() }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun useBox(box: Box): Long {
          return swiftjava_SwiftModule_useBox_box(box.__ptr())
        }
        """
      ]
    )
  }

  @Test
  func customTypeAsParameter_topLevel_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Box { public init() {} public func get() -> Int { 0 } }
        public func useBox(box: Box) -> Int { box.get() }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_useBox_box")
        public func swiftjava_SwiftModule_useBox_box(_ box: UnsafeRawPointer) -> Int {
          return useBox(box: (Unmanaged<AnyObject>.fromOpaque(box).takeUnretainedValue() as! Box))
        }
        """
      ]
    )
  }

  @Test
  func customTypeProperty_getter_kotlin() throws {
    try assertOutput(
      input: """
        public class Child { public init() {} }
        public class Parent {
          public init() {}
          public var child: Child { Child() }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        val child: Child
          get() {
            return Child(wrapSwiftObject { swiftjava_SwiftModule_Parent_child_kn_get(__ptr()) })
          }
        """
      ]
    )
  }

  @Test
  func customTypeProperty_getter_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Child { public init() {} }
        public class Parent {
          public init() {}
          public var child: Child { Child() }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Parent_child_kn_get")
        public func swiftjava_SwiftModule_Parent_child_kn_get(_ self: UnsafeRawPointer) -> UnsafeMutableRawPointer {
            let _result = (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Parent).child as AnyObject
            return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
        }
        """
      ]
    )
  }

  @Test
  func customTypeAsParameterAndReturn_method_kotlin() throws {
    try assertOutput(
      input: """
        public class Vec {
          public init() {}
          public func plus(other: Vec) -> Vec { other }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun plus(other: Vec): Vec {
          return Vec(wrapSwiftObject { swiftjava_SwiftModule_Vec_plus_other(other.__ptr(), __ptr()) })
        }
        """
      ]
    )
  }

  // MARK: - Skips (throwing / un-lowerable signatures)

  @Test
  func throwingTopLevelFunction_isSkipped() throws {
    try assertOutput(
      input: "public func risky() throws -> Int { 0 }",
      .kotlinNative,
      .java,
      expectedChunks: [
        "// Skipped risky: throwing functions are not supported in kotlinNative mode"
      ],
      notExpectedChunks: ["swiftjava_SwiftModule_risky"]
    )
  }

  @Test
  func throwingTopLevelFunction_noSwiftThunk() throws {
    try assertOutput(
      input: "public func risky() throws -> Int { 0 }",
      .kotlinNative,
      .swift,
      expectedChunks: [],
      notExpectedChunks: ["swiftjava_SwiftModule_risky"]
    )
  }

  @Test
  func throwingMethod_isSkipped() throws {
    try assertOutput(
      input: """
        public class Box {
          public init() {}
          public func risky() throws -> Int { 0 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [],
      notExpectedChunks: ["fun risky", "swiftjava_SwiftModule_Box_risky"]
    )
  }

  @Test
  func throwingMethod_noSwiftThunk() throws {
    try assertOutput(
      input: """
        public class Box {
          public init() {}
          public func risky() throws -> Int { 0 }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [],
      notExpectedChunks: ["swiftjava_SwiftModule_Box_risky"]
    )
  }

  @Test
  func inoutParameterMethod_kotlin() throws {
    // A class method with an `inout Int` parameter surfaces as `Inout<Long>`, with
    // the value marshalled through a native cell (self is a non-mutable class box).
    try assertOutput(
      input: """
        public class Box {
          public init() {}
          public func scale(x: inout Int) {}
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        fun scale(x: Inout<Long>): Unit {
          memScoped {
            val x_cell = alloc<LongVar>()
            x_cell.value = x.unsafeValue
            swiftjava_SwiftModule_Box_scale_x(x_cell.ptr.rawValue, __ptr())
            x.unsafeValue = x_cell.value
          }
        }
        """
      ]
    )
  }

  @Test
  func inoutParameterMethod_swiftThunk() throws {
    try assertOutput(
      input: """
        public class Box {
          public init() {}
          public func scale(x: inout Int) {}
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Box_scale_x")
        public func swiftjava_SwiftModule_Box_scale_x(_ x: UnsafeMutableRawPointer, _ self: UnsafeRawPointer) {
            var _x = x.assumingMemoryBound(to: Int.self).pointee
            let _self = Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Box
            _self.scale(x: &_x)
            x.assumingMemoryBound(to: Int.self).pointee = _x
        }
        """
      ]
    )
  }

  // MARK: - Qualified identity (nested / same-simple-name types)

  @Test
  func nestedType_usesFlatNameForClassAndDestroy_kotlin() throws {
    // A nested type maps to a wrapper named by its flat (qualified) name so it
    // cannot collide with a top-level type of the same simple name (issue #4).
    try assertOutput(
      input: """
        public struct Outer {
          public struct Box {
            public init() {}
            public func get() -> Int { 0 }
          }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        "class Outer_Box internal constructor(val obj: NSObject) : SwiftCopyable {",
        "constructor() : this(wrapSwiftObject { swiftjava_SwiftModule_Outer_Box_init() })",
      ]
    )
  }

  @Test
  func nestedType_destroyThunkUsesQualifiedSwiftType() throws {
    // The C symbol uses the flat name; the Swift type reference is qualified.
    // The destroy thunk itself is now type-erased (`Unmanaged<AnyObject>`), so the
    // qualified Swift type only appears in the init thunk that constructs the box.
    try assertOutput(
      input: """
        public struct Outer {
          public struct Box {
            public init() {}
          }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Outer_Box_init")
        public func swiftjava_SwiftModule_Outer_Box_init() -> UnsafeMutableRawPointer {
            let _result = Outer.Box() as AnyObject
            return Unmanaged<AnyObject>.passRetained(_result).autorelease().toOpaque()
        }
        """
      ]
    )
  }
  // MARK: - Class subscript

  @Test
  func classSubscript_getSet_kotlin() throws {
    try assertOutput(
      input: """
        public class IntBox {
          public init() {}
          public subscript(index: Int) -> Int {
            get { 0 }
            set {}
          }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        operator fun get(index: Long): Long {
          return swiftjava_SwiftModule_IntBox_subscript_kn_get(index, __ptr())
        }
        """,
        """
        operator fun set(index: Long, newValue: Long) {
          swiftjava_SwiftModule_IntBox_subscript_kn_set(index, newValue, __ptr())
        }
        """,
      ]
    )
  }

  @Test
  func classSubscript_getterThunk_swift() throws {
    try assertOutput(
      input: """
        public class IntBox {
          public init() {}
          public subscript(index: Int) -> Int { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_IntBox_subscript_kn_get")
        public func swiftjava_SwiftModule_IntBox_subscript_kn_get(_ index: Int, _ self: UnsafeRawPointer) -> Int {
          return (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! IntBox)[index]
        }
        """,
      ]
    )
  }

  @Test
  func classSubscript_setterThunk_swift() throws {
    try assertOutput(
      input: """
        public class IntBox {
          public init() {}
          public subscript(index: Int) -> Int { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_IntBox_subscript_kn_set")
        public func swiftjava_SwiftModule_IntBox_subscript_kn_set(_ index: Int, _ newValue: Int, _ self: UnsafeRawPointer) {
          (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! IntBox)[index] = newValue
        }
        """,
      ]
    )
  }

  // MARK: - Struct subscript

  @Test
  func structSubscript_getter_kotlin() throws {
    // The getter is a read-only `operator fun get` on the value class.
    try assertOutput(
      input: """
        public struct IntArray {
          public init() {}
          public subscript(index: Int) -> Int { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        operator fun get(index: Long): Long {
          return swiftjava_SwiftModule_IntArray_subscript_kn_get(index, __ptr())
        }
        """,
      ]
    )
  }

  @Test
  func structSubscript_setterInoutExtension_kotlin() throws {
    // The mutating setter is an `Inout<IntArray>.set` extension: call the swap thunk
    // (which returns the re-boxed value) and store it back into the holder.
    try assertOutput(
      input: """
        public struct IntArray {
          public init() {}
          public subscript(index: Int) -> Int { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        operator fun Inout<IntArray>.set(index: Long, newValue: Long) {
          memScoped {
            val self_slot = alloc<COpaquePointerVar>()
            self_slot.value = interpretCPointer<CPointed>(unsafeValue.__ptr())
            swiftjava_SwiftModule_IntArray_subscript_kn_set(index, newValue, self_slot.ptr.rawValue)
            unsafeValue = IntArray(wrapSwiftObject { self_slot.value!!.rawValue })
          }
        }
        """,
      ]
    )
  }

  @Test
  func structSubscript_setterThunk_swap_swift() throws {
    try assertOutput(
      input: """
        public struct IntArray {
          public init() {}
          public subscript(index: Int) -> Int { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_IntArray_subscript_kn_set")
        public func swiftjava_SwiftModule_IntArray_subscript_kn_set(_ index: Int, _ newValue: Int, _ self: UnsafeMutableRawPointer) {
            let self_box = self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
            var _self = Unmanaged<AnyObject>.fromOpaque(self_box).takeUnretainedValue() as! IntArray
            _self[index] = newValue
            self.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee = Unmanaged<AnyObject>.passRetained(_self as AnyObject).autorelease().toOpaque()
        }
        """,
      ]
    )
  }

  // MARK: - Multi-argument subscript

  @Test
  func multiArgSubscript_kotlin() throws {
    try assertOutput(
      input: """
        public class Matrix {
          public init() {}
          public subscript(row: Int, col: Int) -> Double { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        operator fun get(row: Long, col: Long): Double {
          return swiftjava_SwiftModule_Matrix_subscript_kn_get(row, col, __ptr())
        }
        """,
        """
        operator fun set(row: Long, col: Long, newValue: Double) {
          swiftjava_SwiftModule_Matrix_subscript_kn_set(row, col, newValue, __ptr())
        }
        """,
      ]
    )
  }

  @Test
  func multiArgSubscript_getterThunk_swift() throws {
    try assertOutput(
      input: """
        public class Matrix {
          public init() {}
          public subscript(row: Int, col: Int) -> Double { get { 0 } set {} }
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [
        """
        public func swiftjava_SwiftModule_Matrix_subscript_kn_get(_ row: Int, _ col: Int, _ self: UnsafeRawPointer) -> Double {
          return (Unmanaged<AnyObject>.fromOpaque(self).takeUnretainedValue() as! Matrix)[row, col]
        }
        """,
      ]
    )
  }

  // MARK: - Read-only subscript

  @Test
  func readOnlySubscript_noSetter_kotlin() throws {
    try assertOutput(
      input: """
        public class IntBox {
          public init() {}
          public subscript(index: Int) -> Int { 0 }
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [
        """
        operator fun get(index: Long): Long {
          return swiftjava_SwiftModule_IntBox_subscript_kn_get(index, __ptr())
        }
        """,
      ],
      notExpectedChunks: [
        "operator fun set",
      ]
    )
  }
}
