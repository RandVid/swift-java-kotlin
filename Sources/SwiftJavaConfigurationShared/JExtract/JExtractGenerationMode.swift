//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Determines which source generation mode JExtract should be using: JNI or Foreign Function and Memory.
public enum JExtractGenerationMode: String, Sendable, Codable {
  /// Foreign Value and Memory API
  case ffm

  /// Java Native Interface
  case jni

  /// Kotlin source delegating to generated Java FFM bindings (JVM target)
  case kotlin

  /// Kotlin/Native source calling the Swift `@_cdecl` C thunks directly via cinterop (no JVM)
  case kotlinNative

  public static var `default`: JExtractGenerationMode {
    .ffm
  }
}
