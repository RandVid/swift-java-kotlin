package org.swift.swiftkit.kn

/**
 * A Kotlin wrapper over a Swift *value type* (struct) that can produce an
 * independent copy of itself. Generated struct wrappers implement this so that
 * [Inout] can preserve value semantics (copy on the way in and out).
 *
 * Reference types (classes) do NOT implement this — they are shared by reference.
 */
public interface SwiftCopyable {
    public fun copy(): Any
}
