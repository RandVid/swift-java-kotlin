package com.example.kotlinnative

import com.example.kotlinnative.cinterop.swiftjava_SimpleSwiftLib_Counter_init_start
import kotlinx.cinterop.interpretObjCPointer
import platform.darwin.NSObject

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

    println("\n11. Calling function with UInt8 parameters and return:")
    val ubyteSum = addUInt8(10u, 20u)
    println("   addUInt8(10, 20) = $ubyteSum")

    println("\n12. Calling function with UInt16 parameters and return:")
    val ushortSum = addUInt16(1000u, 2000u)
    println("   addUInt16(1000, 2000) = $ushortSum")

    println("\n13. Calling function with UInt32 parameters and return:")
    val uintSum = addUInt32(1_000_000u, 2_000_000u)
    println("   addUInt32(1_000_000, 2_000_000) = $uintSum")

    println("\n14. Calling function with UInt64 parameters and return:")
    val ulongSum = addUInt64(1_000_000_000uL, 2_000_000_000uL)
    println("   addUInt64(1_000_000_000, 2_000_000_000) = $ulongSum")

    printMessage("aboba")
    val a = swiftjava_SimpleSwiftLib_Counter_init_start(5L)
    printMessage("aboba")
    val ahahah = a!!
    printMessage("aboba")
    val b = ahahah.rawValue
    printMessage("aboba")
    val c = interpretObjCPointer<NSObject>(b)
    printMessage("aboba")

    println("\n=== All Kotlin/Native -> Swift cinterop calls successful! ===")
}
