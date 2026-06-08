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

    println("\n5. Calling void function with String parameter:")
    printMessage("   This message is printed from Swift!")

//    for (i in 1..1000) {
//        println("   Kotlin Iteration $i")
//        printMessage("   Swift Iteration $i")
//    }

    println("\n6. Calling function with String parameter and return:")
    val wassup = greet("Fellow Kotliner")
    println("   greet(\"Fellow Kotliner\") = $wassup")

    println("\n7. Calling function with Int8 parameters and return:")
    val byteSum = addInt8(10, 20)
    println("   addInt8(10, 20) = $byteSum")

    println("\n8. Calling function with Int16 parameters and return:")
    val shortSum = addInt16(1000, 2000)
    println("   addInt16(1000, 2000) = $shortSum")

    println("\n9. Calling function with Int64 parameters and return:")
    val longSum = addInt64(1_000_000_000L, 2_000_000_000L)
    println("   addInt64(1_000_000_000, 2_000_000_000) = $longSum")

    println("\n10. Calling function with Float parameters and return:")
    val floatSum = addFloat(1.5f, 2.5f)
    println("   addFloat(1.5, 2.5) = $floatSum")

    println("\n=== All Kotlin/Native -> Swift cinterop calls successful! ===")
}
