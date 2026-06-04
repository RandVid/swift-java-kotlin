//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

package com.example.kotlinnative

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

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
}
