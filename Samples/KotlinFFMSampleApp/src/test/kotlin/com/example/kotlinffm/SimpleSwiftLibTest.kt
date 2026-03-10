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

package com.example.kotlinffm

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

/**
 * Test suite for Kotlin FFM delegation to Swift functions.
 *
 * This test verifies that:
 * 1. The Kotlin generator creates proper delegation code
 * 2. The generated Kotlin functions call the Java FFM classes
 * 3. The Java FFM classes successfully call Swift via native FFM
 *
 * Architecture: Kotlin Test → Generated Kotlin → Generated Java FFM → Swift Native
 */
class SimpleSwiftLibTest {

    @Test
    fun `test void function - helloWorld`() {
        // Should not throw - void function
        assertDoesNotThrow {
            helloWorld()
        }
    }

    @Test
    fun `test Int parameters and return - add`() {
        val result = add(10, 32)
        assertEquals(42, result, "add(10, 32) should return 42")
    }

    @Test
    fun `test Boolean return - isPositive`() {
        assertTrue(isPositive(42), "isPositive(42) should be true")
        assertFalse(isPositive(-10), "isPositive(-10) should be false")
        assertFalse(isPositive(0), "isPositive(0) should be false")
    }

    @Test
    fun `test Double parameters and return - divide`() {
        val result = divide(10.0, 2.0)
        assertEquals(5.0, result, 0.001, "divide(10.0, 2.0) should return 5.0")
    }

    @Test
    fun `test void function with String parameter - printMessage`() {
        // Should not throw - void function with parameter
        assertDoesNotThrow {
            printMessage("Hello from Kotlin test!")
        }
    }

    @Test
    fun `test edge cases - zero and negative numbers`() {
        assertEquals(0, add(0, 0), "add(0, 0) should return 0")
        assertEquals(-5, add(-10, 5), "add(-10, 5) should return -5")
    }
}
