package org.swift.swiftkit.kn

/**
 * A mutable holder for a Swift `inout` argument of a *value type* (struct).
 *
 * A Swift `inout Point` surfaces as `Inout<Point>`. It preserves value semantics:
 * [value] copies on read and on write (via [SwiftCopyable.copy]) so the caller's
 * value can't be aliased by whatever the callee stored, and vice versa. Generated
 * mutation extensions (`var Inout<Point>.x`, `fun Inout<Point>.translate(…)`) use
 * [unsafeValue] to mutate the stored value in place without the extra copy.
 *
 * For a non-copyable `T` (a primitive or a reference-type wrapper) [copyIfNeeded]
 * is a no-op, so `Inout<T>` behaves like a plain box.
 *
 * [onChange], when non-null, is invoked with the new stored value after every write
 * (through [value] or [unsafeValue]). This powers *connected* nested field holders:
 * `Inout<Rect>.topLeft` returns an `Inout<Point>` whose `onChange` re-embeds the
 * point into the parent `Rect`, so `rect.topLeft.x = …` mutates `rect` (and chains
 * up the tree). A standalone `Inout` has `onChange == null`.
 */
public class Inout<T>(value: T, private val onChange: ((T) -> Unit)? = null) {
    private var storedValue: T = copyIfNeeded(value)

    public var value: T
        get() = copyIfNeeded(storedValue)
        set(newValue) {
            storedValue = copyIfNeeded(newValue)
            onChange?.invoke(storedValue)
        }

    /** Direct access to the stored value with no defensive copy (used internally). */
    public var unsafeValue: T
        get() = storedValue
        set(newValue) {
            storedValue = newValue
            onChange?.invoke(newValue)
        }

    @Suppress("UNCHECKED_CAST")
    private fun copyIfNeeded(value: T): T =
        if (value is SwiftCopyable) {
            value.copy() as T
        } else {
            value
        }
}
