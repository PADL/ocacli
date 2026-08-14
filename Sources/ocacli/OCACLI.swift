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
  @Option(name: [.customShort("c"), .customLong("command")], help: "Commands to execute")
  var commandsToExecute: [String] = []
  @Option(name: [.customShort("f"), .customLong("flags")], help: "Context flags")
  var contextFlags: [ContextFlags] = []
  @Option(name: [.short, .long], help: "Device port")
  var port: Int = 65000
  @Flag(name: [.customShort("U"), .customLong("udp")], help: "Use UDP instead of TCP")
  var datagram = false
  @Flag(
    name: [.customShort("w"), .customLong("websocket")],
    help: "Use WebSocket instead of TCP"
  )
  var webSocket = false
  @Flag(
    name: [.customShort("S"), .long],
    help: "Use TLS over TCP; combine with -U for DTLS over UDP"
  )
  var tls = false
  @Option(name: .long, help: "TLS PSK identity (default: OCA-PSK)")
  var pskIdentity: String?
  @Option(name: .long, help: "TLS PSK key, hex-encoded")
  var pskKey: String?
  @Option(name: .customLong("cert"), help: "TLS client certificate PEM file")
  var certFile: String?
  @Option(name: .customLong("key"), help: "TLS client private key PEM file")
  var keyFile: String?
  @Option(name: .customLong("pkcs12"), help: "TLS client PKCS#12 bundle path")
  var pkcs12File: String?
  @Option(
    name: .customLong("pkcs12-password"),
    help: "PKCS#12 bundle password (env: OCACLI_PKCS12_PASSWORD; prompted if omitted)"
  )
  var pkcs12Password: String?
  @Flag(
    name: [.customShort("k"), .long],
    help: "Disable TLS server certificate verification (cert credentials only; for testing)"
  )
  var insecure = false
  @Option(name: .customLong("cacert"), help: "PEM CA bundle for TLS server-cert verification")
  var caCertFile: String?
  @Option(name: .customLong("crl-file"), help: "PEM CRL bundle for TLS revocation checking")
  var crlFile: String?
  @Flag(name: .long, help: "Enable TLS revocation checking against leaf certificate")
  var checkRevocation = false
  @Flag(name: .long, help: "Enable TLS revocation checking across the full chain")
  var checkRevocationAll = false
  @Option(name: [.customShort("P"), .long], help: "Domain socket path")
  var path: String?
  #if canImport(Darwin)
  @Option(name: [.customShort("M"), .customLong("mach")], help: "Mach port bootstrap service name")
  var machServiceName: String?
  #endif
  @Flag(name: [.customShort("a"), .long], help: "Attempt to reconnect on disconnection")
  var automaticReconnect = false
  @Flag(name: [.customShort("r"), .long], help: "Resolve device action objects at startup")
  var resolveDeviceTree = false
  @Flag(
    name: [.customShort("s"), .customLong("subscribe-properties")],
    help: "Subscribe to property change events"
  )
  var cacheProperties = false
  @Option(name: [.customShort("l"), .long], help: "Log level")
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
    let endpoint = hostname ?? path ?? machServiceName
    let endpointOptions = "--hostname, --path or --mach"
    #else
    let endpoint = hostname ?? path
    let endpointOptions = "--hostname or --path"
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

    #if canImport(Darwin)
    let isLocal = path != nil || machServiceName != nil
    #else
    let isLocal = path != nil
    #endif
    if tls, isLocal {
      throw ValidationError(
        "--tls cannot be combined with --path or --mach (TLS is only supported over TCP/UDP)."
      )
    }
    if !tls, caCertFile != nil || insecure {
      throw ValidationError("--cacert and --insecure require --tls.")
    }
    if UInt16(exactly: port) == nil {
      throw ValidationError("'\(port)' is not a port number.")
    }
  }

  private func initContext() async throws -> Context {
    var logger = Logger(label: "com.padl.ocacli")

    if let logLevel, let level = Logger.Level(rawValue: logLevel) {
      logger.logLevel = level
    }

    var contextFlags: ContextFlags = [
      .enableRolePathLookupCache,
      .supportsFindActionObjectsByPath,
    ]
    contextFlags = self.contextFlags.reduce(contextFlags) { result, value in
      result.union(value)
    }

    let deviceEndpointInfo: DeviceEndpointInfo

    if automaticReconnect {
      contextFlags.insert(.automaticReconnect)
    }
    if resolveDeviceTree {
      contextFlags.insert(.refreshDeviceTreeOnConnection)
    }
    if cacheProperties {
      contextFlags.insert([.cacheProperties, .subscribePropertyEvents])
    }

    guard let port = UInt16(exactly: port) else {
      throw Ocp1Error.serviceResolutionFailed
    }

    #if canImport(Darwin)
    let _machServiceName = machServiceName
    #else
    let _machServiceName: String? = nil
    #endif
    let tlsCredential: Ocp1TLSCredential? = try Self._resolveTLSCredential(
      tls: tls,
      pskIdentity: pskIdentity,
      pskKey: pskKey,
      certFile: certFile,
      keyFile: keyFile,
      pkcs12File: pkcs12File,
      pkcs12Password: pkcs12Password
    )
    let revocation = try Self._resolveRevocationOptions(
      tls: tls,
      crlFile: crlFile,
      checkRevocation: checkRevocation,
      checkRevocationAll: checkRevocationAll
    )
    deviceEndpointInfo = Self._resolveEndpointInfo(
      path: path,
      hostname: hostname,
      port: port,
      datagram: datagram,
      webSocket: webSocket,
      tlsCredential: tlsCredential,
      tlsTrustRoots: caCertFile.map { .caFile($0) },
      tlsRevocation: revocation,
      machServiceName: _machServiceName
    )

    return try await Context(
      deviceEndpointInfo: deviceEndpointInfo,
      contextFlags: contextFlags,
      logger: logger,
      connectionTimeout: connectionTimeout != nil ? .seconds(connectionTimeout!) : nil,
      responseTimeout: responseTimeout != nil ? .seconds(responseTimeout!) : nil,
      batchSize: batchSize != nil ? UInt32(batchSize!) : nil,
      batchThreshold: batchThreshold != nil ? .milliseconds(batchThreshold!) : nil,
      insecure: insecure
    )
  }

  private static func _resolveEndpointInfo(
    path: String?,
    hostname: String?,
    port: UInt16,
    datagram: Bool,
    webSocket: Bool,
    tlsCredential: Ocp1TLSCredential?,
    tlsTrustRoots: Ocp1TLSTrustRoots?,
    tlsRevocation: Ocp1TLSRevocationOptions,
    machServiceName: String?
  ) -> DeviceEndpointInfo {
    if let tlsCredential {
      if datagram {
        return .dtls(hostname!, port, tlsCredential, tlsTrustRoots, tlsRevocation)
      } else {
        return .tls(hostname!, port, tlsCredential, tlsTrustRoots, tlsRevocation)
      }
    }
    #if canImport(Darwin)
    if let machServiceName {
      return .machPort(machServiceName)
    }
    #endif
    if let path {
      if datagram {
        return .datagramPath(path)
      } else {
        return .path(path)
      }
    } else {
      if webSocket {
        return .webSocket(hostname!, port)
      } else if datagram {
        return .udp(hostname!, port)
      } else {
        return .tcp(hostname!, port)
      }
    }
  }

  /// Build an `Ocp1TLSCredential` from whichever credential family the user
  /// selected via flags. Exactly one of PSK / cert-file / PKCS#12 must be
  /// supplied alongside `--tls`. The library accepts further credential
  /// shapes (raw in-memory PEM, platform-native identities) that aren't
  /// meaningful from a command line so they aren't exposed here.
  private static func _resolveTLSCredential(
    tls: Bool,
    pskIdentity: String?,
    pskKey: String?,
    certFile: String?,
    keyFile: String?,
    pkcs12File: String?,
    pkcs12Password: String?
  ) throws -> Ocp1TLSCredential? {
    let hasPSK = pskKey != nil
    let hasCertFile = certFile != nil || keyFile != nil
    let hasPKCS12 = pkcs12File != nil

    if !tls {
      if hasPSK || hasCertFile || hasPKCS12 || pskIdentity != nil || pkcs12Password != nil {
        print(
          "error: --psk-identity / --psk-key / --cert / --key / --pkcs12[-password] require --tls"
        )
        throw Ocp1Error.status(.parameterError)
      }
      return nil
    }

    let supplied = [hasPSK, hasCertFile, hasPKCS12].filter { $0 }.count
    guard supplied == 1 else {
      if supplied == 0 {
        print(
          "error: --tls requires a credential: --psk-key, --cert/--key, or --pkcs12"
        )
      } else {
        print(
          "error: --psk-key, --cert/--key and --pkcs12 are mutually exclusive"
        )
      }
      throw Ocp1Error.status(.parameterError)
    }

    if hasPSK {
      guard let pskKey, let keyBytes = Data(hex: pskKey) else {
        print("error: --psk-key must be a hex string")
        throw Ocp1Error.status(.parameterError)
      }
      // Library also enforces this in `Ocp1TLSCredential.validate()`, but
      // catching it up front gives the user a clearer message than the
      // generic parameterError thrown at connect time.
      guard keyBytes.count >= OcaMinimumPreSharedKeyLength else {
        print(
          "error: --psk-key must be at least \(OcaMinimumPreSharedKeyLength) bytes (got \(keyBytes.count))"
        )
        throw Ocp1Error.status(.parameterError)
      }
      let identity = pskIdentity ?? OcaPreSharedKeyIdentityHint
      return .preSharedKey(identity: identity, key: keyBytes)
    }

    if hasCertFile {
      guard let certFile, let keyFile else {
        print("error: --cert and --key must be supplied together")
        throw Ocp1Error.status(.parameterError)
      }
      return .certificateFile(certPath: certFile, keyPath: keyFile)
    }

    // PKCS#12: load the bundle into memory; the library handles parsing.
    guard let pkcs12File else { preconditionFailure() }
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: pkcs12File))
    } catch {
      print("error: could not read PKCS#12 file at \(pkcs12File): \(error)")
      throw Ocp1Error.status(.parameterError)
    }
    let password = Self._resolvePKCS12Password(explicit: pkcs12Password)
    return .pkcs12(data: data, password: password)
  }

  /// Resolve a PKCS#12 password without forcing the user to expose it on
  /// the command line (visible in `ps` listings and shell history). The
  /// CLI argument wins if supplied; otherwise fall back to an environment
  /// variable, then to a `getpass`-style interactive prompt. A nil result
  /// means "no password" — only valid for unencrypted bundles.
  private static func _resolvePKCS12Password(explicit: String?) -> String? {
    if let explicit { return explicit }
    if let env = ProcessInfo.processInfo.environment["OCACLI_PKCS12_PASSWORD"] {
      return env
    }
    // Skip the prompt when stdin isn't a TTY (e.g. piped input) — getpass
    // would either block forever or echo on stderr-only consoles. Returning
    // nil lets the library try a no-password bundle and fail cleanly.
    guard isatty(STDIN_FILENO) != 0 else { return nil }
    guard let cString = getpass("PKCS#12 password: ") else { return nil }
    let password = String(cString: cString)
    return password.isEmpty ? nil : password
  }

  /// Map the `--check-revocation[-all]` and `--crl-file` flags onto the
  /// library's `Ocp1TLSRevocationOptions`. Revocation is off-by-default;
  /// supplying `--crl-file` alone is enough to opt in (without a checking
  /// flag the CRL would just sit unused).
  private static func _resolveRevocationOptions(
    tls: Bool,
    crlFile: String?,
    checkRevocation: Bool,
    checkRevocationAll: Bool
  ) throws -> Ocp1TLSRevocationOptions {
    if !tls, crlFile != nil || checkRevocation || checkRevocationAll {
      print("error: --crl-file / --check-revocation[-all] require --tls")
      throw Ocp1Error.status(.parameterError)
    }
    var flags: Ocp1TLSRevocationOptions.Flags = []
    if checkRevocation || crlFile != nil { flags.insert(.enabled) }
    if checkRevocationAll { flags.insert([.enabled, .checkChain]) }
    return Ocp1TLSRevocationOptions(flags: flags, crls: crlFile.map { .crlFile($0) })
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
    if commandsToExecute.isEmpty {
      await session.runInteractively()
    } else {
      await session.run(commandsToExecute)
    }
    await session.finish()
  }
}
