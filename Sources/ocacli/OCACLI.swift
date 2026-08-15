//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import ArgumentParser
import AsyncAlgorithms
import Foundation
import Logging
import SwiftOCA
import SwiftOCASecure

@main
struct OCACLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ocacli",
    abstract: "Control an AES70/OCA device.",
    // -h is the device host name, so help is offered under its long name only
    helpNames: [.long]
  )

  @Option(name: [.short, .long], help: "Device host name")
  var hostname: String?
  @Option(name: [.short, .long], help: "Device port")
  var port: Int = 65000
  @Option(name: [.customShort("P"), .long], help: "Domain socket path")
  var path: String?
  #if canImport(Darwin)
  @Option(name: [.customShort("M"), .long], help: "Mach port bootstrap service name")
  var mach: String?
  #endif
  @Flag(name: [.customShort("U"), .long], help: "Use UDP instead of TCP")
  var udp = false
  @Flag(name: [.short, .long], help: "Use WebSocket instead of TCP")
  var websocket = false

  @OptionGroup(title: "TLS")
  var tlsOptions: TLSOptions

  @Option(name: [.short, .long], help: "Commands to execute")
  var command: [String] = []
  @Option(name: [.short, .long], help: "Context flags")
  var flags: [ContextFlags] = []
  @Flag(name: [.short, .long], help: "Attempt to reconnect on disconnection")
  var automaticReconnect = false
  @Flag(name: [.short, .long], help: "Resolve device action objects at startup")
  var resolveDeviceTree = false
  @Flag(name: [.short, .long], help: "Subscribe to property change events")
  var subscribeProperties = false
  @Option(name: [.short, .long], help: "Log level")
  var logLevel: String?
  @Option(name: [.customShort("t"), .long], help: "Connection timeout (seconds)")
  var connectionTimeout: Int?
  @Option(name: [.customShort("T"), .long], help: "Response timeout (seconds)")
  var responseTimeout: Int?
  @Option(name: [.customShort("B"), .long], help: "Request message batch size (bytes)")
  var batchSize: Int?
  @Option(name: .long, help: "Request message batch threshold (milliseconds)")
  var batchThreshold: Int?

  func validate() throws {
    #if canImport(Darwin)
    let endpoint = hostname ?? path ?? mach
    let endpointOptions = "--hostname, --path or --mach"
    let isLocal = path != nil || mach != nil
    #else
    let endpoint = hostname ?? path
    let endpointOptions = "--hostname or --path"
    let isLocal = path != nil
    #endif

    guard endpoint != nil else {
      throw ValidationError("A device must be given with \(endpointOptions).")
    }

    if let logLevel, Logger.Level(rawValue: logLevel) == nil {
      throw ValidationError(
        "'\(logLevel)' is not a log level: expected one of " +
          Logger.Level.allCases.map(\.rawValue).joined(separator: ", ") + "."
      )
    }

    if tlsOptions.tls, isLocal {
      throw ValidationError(
        "--tls cannot be combined with --path or --mach (TLS is only supported over TCP/UDP)."
      )
    }

    if UInt16(exactly: port) == nil {
      throw ValidationError("'\(port)' is not a port number.")
    }

    if let batchSize, UInt32(exactly: batchSize) == nil {
      throw ValidationError("'\(batchSize)' is not a batch size.")
    }

    // a duration is measured in attoseconds, so one made from a large enough number of seconds
    // traps rather than being merely absurd
    for (value, option, limit) in [
      (connectionTimeout, "--connection-timeout", Self.longestTimeoutInSeconds),
      (responseTimeout, "--response-timeout", Self.longestTimeoutInSeconds),
      (batchThreshold, "--batch-threshold", Self.longestTimeoutInSeconds * 1000),
    ] {
      if let value, !(0...limit).contains(value) {
        throw ValidationError("\(option) must be between 0 and \(limit).")
      }
    }
  }

  /// a day, which is longer than any of these could sensibly be
  private static let longestTimeoutInSeconds = 86400

  private func initContext() async throws -> Context {
    var logger = Logger(label: "com.padl.ocacli")
    if let logLevel, let level = Logger.Level(rawValue: logLevel) {
      logger.logLevel = level
    }

    var contextFlags: ContextFlags = [
      .enableRolePathLookupCache,
      .supportsFindActionObjectsByPath,
    ]
    contextFlags = flags.reduce(contextFlags) { $0.union($1) }

    if automaticReconnect {
      contextFlags.insert(.automaticReconnect)
    }
    if resolveDeviceTree {
      contextFlags.insert(.refreshDeviceTreeOnConnection)
    }
    if subscribeProperties {
      contextFlags.insert([.cacheProperties, .subscribePropertyEvents])
    }

    return try await Context(
      deviceEndpointInfo: endpointInfo(),
      contextFlags: contextFlags,
      logger: logger,
      connectionTimeout: connectionTimeout.map { .seconds($0) },
      responseTimeout: responseTimeout.map { .seconds($0) },
      batchSize: batchSize.map { UInt32($0) },
      batchThreshold: batchThreshold.map { .milliseconds($0) },
      insecure: tlsOptions.insecure
    )
  }

  private func endpointInfo() throws -> DeviceEndpointInfo {
    let port = UInt16(exactly: port)!

    if let credential = try tlsOptions.credential() {
      let trustRoots = tlsOptions.trustRoots
      let revocation = tlsOptions.revocationOptions
      return udp
        ? .dtls(hostname!, port, credential, trustRoots, revocation)
        : .tls(hostname!, port, credential, trustRoots, revocation)
    }

    #if canImport(Darwin)
    if let mach {
      return .machPort(mach)
    }
    #endif

    if let path {
      return udp ? .datagramPath(path) : .path(path)
    } else if websocket {
      return .webSocket(hostname!, port)
    } else if udp {
      return .udp(hostname!, port)
    } else {
      return .tcp(hostname!, port)
    }
  }

  func run() async throws {
    LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }

    signal(SIGPIPE, SIG_IGN)

    let context: Context
    do {
      context = try await initContext()
    } catch {
      print(error)
      throw ExitCode(2)
    }

    let session = Session(context: context)
    var succeeded = true
    if command.isEmpty {
      await session.runInteractively()
    } else {
      succeeded = await session.run(command)
    }
    await session.finish()

    guard succeeded else { throw ExitCode.failure }
  }
}
