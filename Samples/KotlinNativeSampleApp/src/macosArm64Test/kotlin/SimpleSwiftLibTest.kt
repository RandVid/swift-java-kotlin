package com.example.kotlinnative

import org.swift.swiftkit.kn.Inout
import kotlin.native.runtime.GC
import kotlin.native.runtime.NativeRuntimeApi
import kotlin.test.Ignore
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
    fun testClass_subscriptGetSet() {
        // On a class both `operator fun get`/`set` are plain members: `c[offset]`.
        val counter = Counter(10L)
        assertEquals(15L, counter[5L])       // get: count + offset
        counter[3L] = 20L                    // set: count = newValue - offset → 17
        assertEquals(17L, counter.currentValue())
        assertEquals(17L, counter[0L])
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

    // Struct support: single `SwiftCopyable` value class + `Inout<Struct>` extensions.

    @Test
    fun testStruct_constructAndMethod() {
        val p = Point(3L, 4L)
        assertEquals(7L, p.sum())
    }

    @Test
    fun testStruct_propertyAndCustomReturn() {
        val p = Point(1L, 2L)
        assertEquals(1L, p.x)
        assertEquals(2L, p.y)
        val moved = p.translated(10L, 20L)
        assertEquals(11L, moved.x)
        assertEquals(22L, moved.y)
    }

    @Test
    fun testStruct_copyIsIndependentRead() {
        // `copy()` produces a fresh box; reads match the original.
        val p = Point(5L, 6L)
        val c = p.copy()
        assertEquals(5L, c.x)
        assertEquals(6L, c.y)
    }

    // Mutation via `Inout<Struct>` extensions: each extension calls the thunk (which
    // returns the re-boxed value) and stores it back into the holder.

    @Test
    fun testStruct_inoutMutatingMethod() {
        val p = Inout(Point(3L, 4L))
        p.scale(2L)
        assertEquals(6L, p.value.x)
        assertEquals(8L, p.value.y)
        assertEquals(14L, p.value.sum())
    }

    @Test
    fun testStruct_inoutSettableProperty() {
        val p = Inout(Point(1L, 2L))
        p.x = 10L
        p.y = 20L
        assertEquals(10L, p.value.x)
        assertEquals(20L, p.value.y)
    }

    @Test
    fun testStruct_inoutPreservesValueSemantics() {
        // Inout(original) stores a copy; mutating the holder does not touch original.
        val original = Point(1L, 2L)
        val io = Inout(original)
        io.x = 10L
        assertEquals(10L, io.value.x)
        assertEquals(1L, original.x)   // original unchanged (value semantics)
    }

    @Test
    fun testStruct_subscriptGetter() {
        // The getter is a read-only member on the value class: `p[index]`.
        val p = Point(3L, 4L)
        assertEquals(3L, p[0L])   // index 0 → x
        assertEquals(4L, p[1L])   // any other index → y
    }

    @Test
    fun testStruct_subscriptSetterInoutExtension() {
        // The setter mutates, so it is an `Inout<Point>.set` extension: `p[i] = v`.
        val p = Inout(Point(1L, 2L))
        p[0L] = 10L
        p[1L] = 20L
        assertEquals(10L, p.value.x)
        assertEquals(20L, p.value.y)
        assertEquals(10L, p.value[0L])
    }

    @Test
    fun testStruct_subscriptPreservesValueSemantics() {
        val original = Point(1L, 2L)
        val io = Inout(original)
        io[0L] = 99L
        assertEquals(99L, io.value.x)
        assertEquals(1L, original.x)   // original unchanged (value semantics)
    }

    // Multi-argument subscripts: `g[row, col]` desugars to get(row, col) / set(row, col, v).

    @Test
    fun testStruct_multiArgSubscript() {
        val g = Inout(Grid(2L, 3L))
        g[0L, 0L] = 5L                 // set (Inout<Grid> extension)
        g[1L, 2L] = 9L
        assertEquals(5L, g.value[0L, 0L])   // get (value class)
        assertEquals(9L, g.value[1L, 2L])
        assertEquals(0L, g.value[0L, 1L])   // untouched cell
    }

    // Subscripts keyed by a custom struct / class argument (boxed index raised in the thunk).

    @Test
    fun testStruct_subscriptWithStructArgument() {
        val key = Point(2L, 3L)
        val bag = PointBag(10L)
        assertEquals(15L, bag[key])         // get: total + x + y = 10 + 2 + 3

        val io = Inout(PointBag(0L))
        io[key] = 20L                        // set: total = 20 - 2 - 3 = 15
        assertEquals(15L, io.value.total)
        assertEquals(20L, io.value[key])     // total + x + y = 15 + 2 + 3
    }

    @Test
    fun testClass_subscriptWithClassArgument() {
        val board = ScoreBoard(100L)
        val counter = Counter(7L)
        assertEquals(107L, board[counter])   // get: base + currentValue = 100 + 7
        board[counter] = 200L                 // set: base = 200 - 7 = 193
        assertEquals(193L, board[Counter(0L)])
    }

    @Test
    fun testStruct_structInoutParameter() {
        val p = Inout(Point(3L, 2L))
        recenter(p, 3, 5)
        assertEquals(6L, p.value.x)
        assertEquals(7L, p.value.y)
    }

    // Custom-type field: whole-field replacement via the connected `Inout<Point>`.
    @Test
    fun testStruct_customTypeFieldWholeReplace() {
        val rect = Inout(Rectangle(Point(0L, 0L), Point(6L, 7L)))
        rect.topLeft.value = Point(3L, 9L)
        assertEquals(3L, rect.value.topLeft.x)
        assertEquals(9L, rect.value.topLeft.y)
        assertEquals(6L, rect.value.bottomRight.x)   // other field untouched
    }

    // Option 2 — connected sub-holder: nested `rect.topLeft.x = …` writes back to rect.
    @Test
    fun testStruct_nestedFieldConnectedMutation() {
        val rect = Inout(Rectangle(Point(0L, 0L), Point(6L, 7L)))
        rect.topLeft.x = 3L
        assertEquals(3L, rect.value.topLeft.x)         // nested write reached the parent
        assertEquals(0L, rect.value.topLeft.y)         // sibling untouched
        assertEquals(6L, rect.value.bottomRight.x)     // other field untouched
    }

    // Option 1 — scoped batched mutation: read once, mutate in the block, write back once.
    @Test
    fun testStruct_nestedFieldScopedMutation() {
        val rect = Inout(Rectangle(Point(1L, 2L), Point(3L, 4L)))
        rect.mutateTopLeft {
            x = 10L
            y = 20L
        }
        assertEquals(10L, rect.value.topLeft.x)
        assertEquals(20L, rect.value.topLeft.y)
        assertEquals(3L, rect.value.bottomRight.x)     // other field untouched
    }

    @Ignore
    @Test
    fun testStruct_staleSubViewClobbersParent() {
        val rect = Inout(Rectangle(Point(0L, 0L), Point(6L, 7L)))

        val staleTopLeft = rect.topLeft        // snapshot of topLeft == (0, 0)

        rect.topLeft.x = 100L                  // mutate via a fresh sub-view
        assertEquals(100L, rect.topLeft.x)     // the intervening write landed on rect

        staleTopLeft.y = 5L                     // stale (0,0) + y=5 → writes (0,5) back into rect

        // The stale write-back overwrote topLeft with its snapshot, losing x=100.
        // Ideally this would be 100; it is 0 — a lost update.
        assertEquals(100L, rect.topLeft.x)
        assertEquals(5L, rect.topLeft.y)
    }

    @Test
    fun testClass_extensionMethodIsImported() {
        val c = Counter(1L)
        c.sixseven()
        assertEquals(67L, c.currentValue())
    }

    // inout support (Inout<T> + native cell marshalling) — primitives persist.

    @Test
    fun testInout_primitiveTopLevel() {
        val v = Inout(10L)
        addInPlace(v, 5L)
        assertEquals(15L, v.value)
    }

    @Test
    fun testInout_primitiveMethodOnClass() {
        val c = Counter(42L)
        val out = Inout(0L)
        c.readInto(out)
        assertEquals(42L, out.value)
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

    fun testMemory_cleanerHandlesStructCorrectly_helper() {
        val before = counterDeinitCount()
        val h = Holder()
        assertEquals(67L, h.value())
        assertTrue(isWeakRefAlive())
    }

    @Test
    @OptIn(NativeRuntimeApi::class)
    fun testMemory_cleanerHandlesStructCorrectly() {
        GC.collect()
        testMemory_cleanerHandlesStructCorrectly_helper()
        GC.collect()
        assertFalse(isWeakRefAlive())
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
