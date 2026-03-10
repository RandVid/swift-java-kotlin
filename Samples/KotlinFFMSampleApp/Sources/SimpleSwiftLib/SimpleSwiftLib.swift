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

// Minimal Swift library for testing Kotlin FFM delegation
// Contains only primitive types that are supported by the Kotlin generator

public func helloWorld() {
  print("Hello from Swift!")
}

public func add(a: Int, b: Int) -> Int {
  return a + b
}

public func greet(name: String) -> String {
  return "Hello, \(name)!"
}

public func isPositive(value: Int) -> Bool {
  return value > 0
}

public func divide(a: Double, b: Double) -> Double {
  return a / b
}

public func printMessage(message: String) {
  print(message)
}
