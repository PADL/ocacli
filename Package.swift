// swift-tools-version:6.0

import Foundation
import PackageDescription

// When OCA_CMAKE_STAGE is set, the SwiftOCA + swift-async-algorithms +
// swift-log + swift-system deps are not pulled into the target build graph;
// instead swiftc/ld are pointed at a pre-installed CMake stage (lib +
// lib/swift/<os>) and the modules are linked as bare .so files. Empty value
// means "use the toolchain's default search paths". OcaFirmwareImageContainer
// reads the same env var and applies the same gating.
let cmakeStageEnv = ProcessInfo.processInfo.environment["OCA_CMAKE_STAGE"]
let useCMakeStage = cmakeStageEnv != nil
let cmakeStagePath: String? = {
  guard let v = cmakeStageEnv, !v.isEmpty else { return nil }
  return v
}()

#if os(Linux)
let swiftOS = "linux"
#elseif os(macOS)
let swiftOS = "macosx"
#elseif os(Windows)
let swiftOS = "windows"
#else
let swiftOS = "linux"
#endif

func stageSwiftSettings() -> [SwiftSetting] {
  guard let prefix = cmakeStagePath else { return [] }
  return [.unsafeFlags([
    "-I", "\(prefix)/lib/swift/\(swiftOS)",
    "-Xcc", "-I\(prefix)/include",
  ])]
}

func stageLinkerSettings(linking modules: [String]) -> [LinkerSetting] {
  guard useCMakeStage else { return [] }
  var settings: [LinkerSetting] = []
  if let prefix = cmakeStagePath {
    settings.append(.unsafeFlags([
      "-L", "\(prefix)/lib",
      "-L", "\(prefix)/lib/swift/\(swiftOS)",
    ]))
  }
  for module in modules {
    settings.append(.linkedLibrary(module))
  }
  return settings
}

let cliStagedModules = [
  "SwiftOCA",
  "SwiftOCASecure",
  "AsyncAlgorithms",
  "Logging",
  "SystemPackage",
]

let cliDeps: [Target.Dependency] = useCMakeStage ? [
  "OcaFirmwareImageContainer",
  .product(name: "Algorithms", package: "swift-algorithms"),
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  .product(name: "Crypto", package: "swift-crypto"),
  .product(name: "CommandLineKit", package: "swift-commandlinekit"),
] : [
  "SwiftOCA",
  .product(name: "SwiftOCASecure", package: "SwiftOCA"),
  "OcaFirmwareImageContainer",
  .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
  .product(name: "Algorithms", package: "swift-algorithms"),
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  .product(name: "Logging", package: "swift-log"),
  .product(name: "Crypto", package: "swift-crypto"),
  .product(name: "CommandLineKit", package: "swift-commandlinekit"),
]

let package = Package(
  name: "ocacli",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .executable(
      name: "ocacli",
      targets: ["ocacli"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/PADL/SwiftOCA", branch: "main"),
    .package(url: "https://github.com/PADL/OcaFirmwareImageContainer", branch: "main"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.10.0"),
    .package(url: "https://github.com/objecthub/swift-commandlinekit", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "ocacli",
      dependencies: cliDeps,
      swiftSettings: stageSwiftSettings(),
      linkerSettings: stageLinkerSettings(linking: cliStagedModules)
    ),
  ],
  swiftLanguageVersions: [.v5]
)
