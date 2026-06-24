package org.swift.swiftkit.kn

import kotlinx.cinterop.COpaquePointer
import kotlin.concurrent.AtomicInt

/**
 * Opaque box handle for a Swift-allocated object (Option B allocation model).
 *
 * Holds an opaque pointer to a Swift-allocated box and runs the per-type
 * `_destroy` thunk exactly once — either deterministically via `close()` on
 * the owning wrapper, or automatically when the wrapper is garbage-collected
 * via `createCleaner`.
 */
public class SwiftHandle(
    private val ptr: COpaquePointer,
    private val destroyFn: (COpaquePointer) -> Unit,
) {
    private val destroyed = AtomicInt(0)

    public fun ensureAlive(): COpaquePointer {
        check(destroyed.value == 0) { "Swift object already destroyed" }
        return ptr
    }

    public fun destroy() {
        if (destroyed.compareAndSet(0, 1)) destroyFn(ptr)
    }
}
