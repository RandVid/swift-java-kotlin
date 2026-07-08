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
          internal fun __ptr(): COpaquePointer = interpretCPointer<CPointed>(__obj.objcPtr())!!
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
          return Unmanaged<Counter>.fromOpaque(self).takeUnretainedValue().add(x: x)
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
          val ptr = swiftjava_SwiftModule_Greeter_greet_name(name.cstr, __ptr()) ?: return ""
          val result = ptr.toKString()
          free(ptr)
          return result
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

  // MARK: - Struct (uniform box path)

  @Test
  func struct_wrapperAndMethod_kotlin() throws {
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
        """
        class Point internal constructor(private val __obj: NSObject) {
        """,
        """
        fun sum(): Long {
          return swiftjava_SwiftModule_Point_sum(__ptr())
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
          return useBox(box: Unmanaged<Box>.fromOpaque(box).takeUnretainedValue())
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
            let _result = Unmanaged<Parent>.fromOpaque(self).takeUnretainedValue().child as AnyObject
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
  func inoutParameterMethod_isSkipped() throws {
    // `Int` maps via swiftTypeToKotlin, but an `inout` parameter cannot be
    // C-lowered, so the member must be skipped on every artifact (issue #3).
    try assertOutput(
      input: """
        public class Box {
          public init() {}
          public func scale(x: inout Int) {}
        }
        """,
      .kotlinNative,
      .java,
      expectedChunks: [],
      notExpectedChunks: ["fun scale", "swiftjava_SwiftModule_Box_scale"]
    )
  }

  @Test
  func inoutParameterMethod_noSwiftThunk() throws {
    try assertOutput(
      input: """
        public class Box {
          public init() {}
          public func scale(x: inout Int) {}
        }
        """,
      .kotlinNative,
      .swift,
      expectedChunks: [],
      notExpectedChunks: ["swiftjava_SwiftModule_Box_scale"]
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
        "class Outer_Box internal constructor(private val __obj: NSObject) {",
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
}
