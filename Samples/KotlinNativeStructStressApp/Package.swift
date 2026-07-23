// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import Foundation
import PackageDescription

let package = Package(
  name: "KotlinNativeStructStressApp",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .library(
      name: "StressLib",
      type: .dynamic,
      targets: ["StressLib"]
    )
  ],
  dependencies: [
    .package(name: "swift-java", path: "../../")
  ],
  targets: [
    .target(
      name: "StressLib",
      dependencies: [
        .product(name: "SwiftJava", package: "swift-java"),
        .product(name: "SwiftRuntimeFunctions", package: "swift-java"),
      ],
      exclude: [
        "swift-java.config"
      ],
      swiftSettings: [
        .swiftLanguageMode(.v5),
      ],
      plugins: [
        .plugin(name: "JExtractSwiftPlugin", package: "swift-java")
      ]
    )
  ]
)
