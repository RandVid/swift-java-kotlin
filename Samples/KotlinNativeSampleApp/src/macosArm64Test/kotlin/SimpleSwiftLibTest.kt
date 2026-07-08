package com.example.kotlinnative

import com.example.kotlinnative.cinterop.swiftjava_SimpleSwiftLib_Counter_init_start
import platform.darwin.NSObject
import kotlinx.cinterop.*
import kotlin.native.runtime.GC
import kotlin.native.runtime.NativeRuntimeApi
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

// Integration test: Kotlin/Native -> cinterop -> Swift @_cdecl thunk -> real Swift.
// The generated wrappers live in this same package, so they are callable without
// an explicit import.
class SimpleSwiftLibTest {

    @Test
    fun testAdd() {
        assertEquals(7L, add(3L, 4L))
        assertEquals(0L, add(-5L, 5L))
    }

    @Test
    fun testIsPositive() {
        assertTrue(isPositive(5L))
        assertFalse(isPositive(-1L))
        assertFalse(isPositive(0L))
    }

    @Test
    fun testDivide() {
        assertEquals(2.5, divide(5.0, 2.0))
    }

    @Test
    fun testVoidFunctionDoesNotThrow() {
        helloWorld()
    }

    @Test
    fun testStringParameterDoesNotThrow() {
        // String is marshalled to a null-terminated UTF-8 C string via .cstr.
        printMessage("Hello from Kotlin/Native!")
    }

    @Test
    fun testStringReturn() {
        // greet(name:) returns a Swift-heap-allocated char* that the generated
        // wrapper copies via toKString() and frees via platform.posix.free.
        val result = greet("World")
        assertEquals("Hello, World!", result)
    }

    @Test
    fun testStringReturnEmptyInput() {
        val result = greet("")
        assertEquals("Hello, !", result)
    }

    @Test
    fun testAddInt8() {
        assertEquals(7.toByte(), addInt8(3, 4))
        assertEquals(0.toByte(), addInt8(-5, 5))
    }

    @Test
    fun testAddInt16() {
        assertEquals(3000.toShort(), addInt16(1000, 2000))
        assertEquals(0.toShort(), addInt16(-500, 500))
    }

    @Test
    fun testAddInt64() {
        assertEquals(3_000_000_000L, addInt64(1_000_000_000L, 2_000_000_000L))
        assertEquals(0L, addInt64(Long.MIN_VALUE / 2, -(Long.MIN_VALUE / 2)))
    }

    @Test
    fun testAddFloat() {
        assertEquals(4.0f, addFloat(1.5f, 2.5f))
        assertEquals(0.0f, addFloat(-1.0f, 1.0f))
    }

    @Test
    fun testAddUInt8() {
        assertEquals(30u.toUByte(), addUInt8(10u, 20u))
        assertEquals(UByte.MAX_VALUE, addUInt8((UByte.MAX_VALUE - 0u).toUByte(), 0u))
    }

    @Test
    fun testAddUInt16() {
        assertEquals(3000u.toUShort(), addUInt16(1000u, 2000u))
        assertEquals(0u.toUShort(), addUInt16(0u, 0u))
    }

    @Test
    fun testAddUInt32() {
        assertEquals(3_000_000u, addUInt32(1_000_000u, 2_000_000u))
        assertEquals(0u, addUInt32(0u, 0u))
    }

    @Test
    fun testAddUInt64() {
        assertEquals(3_000_000_000uL, addUInt64(1_000_000_000uL, 2_000_000_000uL))
        assertEquals(0uL, addUInt64(0uL, 0uL))
    }

    // Top-level global variable tests.

    @Test
    fun testGlobalVar_readWrite() {
        globalScore = 42L
        assertEquals(42L, globalScore)
        globalScore = 0L  // reset for other tests
    }

    @Test
    fun testGlobalVar_readOnly() {
        assertEquals("1.0", appVersion)
    }

    // Custom class support: construct, call methods, read a property.

    @Test
    fun testClass_constructAndMethod() {
        val counter = Counter(10L)
        counter.increment(5L)
        assertEquals(15L, counter.currentValue())
    }

    @Test
    fun testClass_propertyGetSet() {
        val counter = Counter(0L)
        counter.value = 42L
        assertEquals(42L, counter.value)
        counter.increment(8L)
        assertEquals(50L, counter.value)
    }

    @Test
    fun testClass_stringReturningMethod() {
        val counter = Counter(7L)
        assertEquals("Counter(7)", counter.describe())
    }

    @Test
    fun testClass_staticFactoryReturnsObject() {
        val counter = Counter.starting(99L)
        assertEquals(99L, counter.currentValue())
    }

    @Test
    fun testClass_methodWithCustomParamAndReturn() {
        val a = Counter(3L)
        val b = Counter(4L)
        val sum = a.plus(b)
        assertEquals(7L, sum.value)
    }

    @Test
    fun testTopLevelFunction_customParamAndReturn() {
        val a = Counter(2L)
        val b = Counter(40L)
        val c = combine(a, b)
        assertEquals(42L, c.currentValue())
    }

    // Struct support (uniform box path).

//    @Test
//    fun testStruct_constructAndMethod() {
//        Point(3L, 4L).use { p ->
//            assertEquals(7L, p.sum())
//        }
//    }
//
//    @Test
//    fun testStruct_propertyAndCustomReturn() {
//        val p = Point(1L, 2L)
//        assertEquals(1L, p.x)
//        assertEquals(2L, p.y)
//        val moved = p.translated(10L, 20L)
//        assertEquals(11L, moved.x)
//        assertEquals(22L, moved.y)
//    }

//    @Test
//    fun testClass_useAfterCloseThrows() {
//        val counter = Counter(1L)
//        counter.close()
//        assertFailsWith<IllegalStateException> {
//            counter.currentValue()
//        }
//    }

    @Test
    fun testClass_extensionMethodIsImported() {
        val c = Counter(1L)
        c.sixseven()
        assertEquals(67L, c.currentValue())
    }

    private fun allocAndDiscard(start: Long) { Counter(start) }

    @Test
    @OptIn(NativeRuntimeApi::class)
    fun testMemory_cleanerDestroysSwiftObject() {
        GC.collect()
        val deinitsBefore = counterDeinitCount()
        allocAndDiscard(1L)
        GC.collect()
        assertEquals(deinitsBefore + 1L, counterDeinitCount())
    }

    private fun copyAndDiscard(copied: Counter) { copied.selfReference() }

    @OptIn(NativeRuntimeApi::class)
    @Test
    fun testMemory_returnedObjectOutlivesProducerAndSharedIdentity() {
        GC.collect()
        val before = counterDeinitCount()
        val a = Counter(7L)
        copyAndDiscard(a)
        GC.collect()
        assertEquals(before, counterDeinitCount())
        assertEquals(7L, a.currentValue())
    }

    @Test
    fun testMemory_returnedFromSwiftOutlivesProducerInSwift() {
        val before = counterDeinitCount()
        val c = retainCounterInSwift(5L)
        assertEquals(before, counterDeinitCount())
        dropSwiftStrongRef()
        assertEquals(before, counterDeinitCount())
        assertEquals(5L, c.currentValue())
    }

    fun weakRefIsNilledAfterClose_helper() {
        val c = retainCounterInSwift(5L)
        storeWeakRef(c)
        assertTrue(isWeakRefAlive())
        dropSwiftStrongRef()
        assertTrue(isWeakRefAlive())
        assertEquals(5L, c.currentValue())
    }

    @OptIn(NativeRuntimeApi::class)
    @Test
    fun testMemory_weakRefIsNilledAfterClose() {
        GC.collect()
        weakRefIsNilledAfterClose_helper()
        GC.collect()
        assertFalse(isWeakRefAlive())
    }

    fun weakRefIsStillAliveIfHasStrongRefInSwift_helper() {
        val c = retainCounterInSwift(5L)
        storeWeakRef(c)
        assertTrue(isWeakRefAlive())
    }

    @OptIn(NativeRuntimeApi::class)
    @Test
    fun testMemory_weakRefIsStillAliveIfHasStrongRefInSwift() {
        GC.collect()
        weakRefIsStillAliveIfHasStrongRefInSwift_helper()
        GC.collect()
        assertTrue(isWeakRefAlive())
        dropSwiftStrongRef()
        assertFalse(isWeakRefAlive())
    }

    // GC-cleaner path tests to test whether the GC can clean up the Swift object

    private fun allocAndDiscardN(n: Int) { repeat(n) { Counter(it.toLong()) } }

    @Test
    @OptIn(NativeRuntimeApi::class)
    fun testMemory_cleanerHandlesBulkObjects() {
        GC.collect()
        val deinitsBefore = counterDeinitCount()
        val n = 50
        allocAndDiscardN(n)   // all 50 frames gone on return
        GC.collect()
        assertEquals(deinitsBefore + n.toLong(), counterDeinitCount())
    }

//    @Test
//    fun testMemory_structReleasesReferenceMember() {
//        val before = counterDeinitCount()
//        val c = Counter(3L)
//        val h = Holder(c)
//        assertEquals(3L, h.value())
//
//        c.close()
//        // The Holder still owns the Counter, so closing `c` must not free it.
//        assertEquals(before, counterDeinitCount())
//        assertEquals(3L, h.value())            // reachable via the struct → still alive
//
//        h.close()
//        // The struct's _destroy runs `deinitialize`, releasing its `counter`
//        // field — the underlying object is now freed exactly once.
//        assertEquals(before + 1L, counterDeinitCount())
//    }
}
