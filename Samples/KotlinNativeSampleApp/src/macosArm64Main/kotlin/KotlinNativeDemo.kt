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

/**
 * Demo application showing Kotlin/Native calling Swift directly via cinterop.
 *
 * The generated wrappers (helloWorld/add/isPositive/divide) live in this same
 * package and call the Swift @_cdecl C thunks through the cinterop bindings —
 * no JVM and no Java FFM layer involved.
 */
fun main() {
    println("=== Kotlin/Native cinterop Demo ===\n")

    println("1. Calling void function:")
    helloWorld()

    println("\n2. Calling function with Int parameters and return:")
    val sum = add(10L, 32L)
    println("   add(10, 32) = $sum")

    println("\n3. Calling function with Boolean return:")
    val isPos = isPositive(42L)
    println("   isPositive(42) = $isPos")

    println("\n4. Calling function with Double parameters and return:")
    val quotient = divide(100.0, 4.0)
    println("   divide(100.0, 4.0) = $quotient")

    println("\n=== All Kotlin/Native -> Swift cinterop calls successful! ===")
}
