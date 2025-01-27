// swift-tools-version:5.9

import Foundation
import PackageDescription

let package = Package(
  name: "ocacli",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(
      name: "ocacli",
      targets: ["ocacli"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/PADL/SwiftOCA", branch: "main"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.10.0"),
    .package(url: "https://github.com/objecthub/swift-commandlinekit", branch: "master"),
  ],
  targets: [
    .executableTarget(
      name: "ocacli",
      dependencies: [
        "SwiftOCA",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "Algorithms", package: "swift-algorithms"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "CommandLineKit", package: "swift-commandlinekit"),
      ]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
