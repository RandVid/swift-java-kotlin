package com.example.kotlinnative

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.assertContentEquals

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

    @Test
    fun testUByteArray() {
        assertEquals(1u, returnUByteArrayFirstElement(ubyteArrayOf(1u, 2u, 3u)))
        assertContentEquals(ubyteArrayOf(4u, 5u, 6u), returnUByteArray(4u, 5u, 6u))
        assertContentEquals(ubyteArrayOf(1u, 4u), returnUByteArraysFirstElements(ubyteArrayOf(1u, 2u, 3u), ubyteArrayOf(4u, 5u, 6u)))
    }
}
