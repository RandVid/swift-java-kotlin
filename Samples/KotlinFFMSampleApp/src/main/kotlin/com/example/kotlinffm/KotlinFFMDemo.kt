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

import com.example.kotlinffm.*

/**
 * Demo application showing Kotlin calling Swift via FFM delegation.
 *
 * This demonstrates that the generated Kotlin code successfully delegates to
 * the Java FFM classes, which in turn call Swift native functions.
 */
fun main() {
    println("=== Kotlin FFM Delegation Demo ===\n")

    println("1. Calling void function:")
    helloWorld()

    println("\n2. Calling function with Int parameters and return:")
    val sum = add(10, 32)
    println("   add(10, 32) = $sum")

    println("\n3. Calling function with Boolean return:")
    val isPos = isPositive(42)
    println("   isPositive(42) = $isPos")

    println("\n4. Calling function with Double parameters and return:")
    val quotient = divide(100.0, 4.0)
    println("   divide(100.0, 4.0) = $quotient")

    println("\n5. Calling void function with String parameter:")
    printMessage("   This message is printed from Swift!")

    println("\n=== All Kotlin → Java FFM → Swift calls successful! ===")
}
