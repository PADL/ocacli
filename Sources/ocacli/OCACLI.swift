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

import AsyncAlgorithms
import CommandLineKit
import Foundation
import Logging
import SwiftOCA
import SwiftOCASecure

@main
final class OCACLI: Command {
  @CommandArgument(short: "h", long: "hostname", description: "Device host name")
  private var hostname: String?
  @CommandArguments(short: "c", long: "command", description: "Commands to execute")
  private var commandsToExecute: [String]
  @CommandArguments(short: "f", long: "flags", description: "Context flags")
  private var contextFlags: [ContextFlags]
  @CommandArgument(short: "p", long: "port", description: "Device port")
  private var port: Int = 65000
  @CommandOption(short: "U", long: "udp", description: "Use UDP instead of TCP")
  private var datagram: Bool
  @CommandOption(short: "w", long: "websocket", description: "Use WebSocket instead of TCP")
  private var webSocket: Bool
  @CommandOption(
    short: "S",
    long: "tls",
    description: "Use TLS over TCP; combine with -U for DTLS over UDP"
  )
  private var tls: Bool
  @CommandArgument(
    long: "psk-identity",
    description: "TLS PSK identity (default: OCA-PSK)"
  )
  private var pskIdentity: String?
  @CommandArgument(long: "psk-key", description: "TLS PSK key, hex-encoded")
  private var pskKey: String?
  @CommandArgument(long: "cert", description: "TLS client certificate PEM file")
  private var certFile: String?
  @CommandArgument(long: "key", description: "TLS client private key PEM file")
  private var keyFile: String?
  @CommandArgument(
    long: "pkcs12",
    description: "TLS client PKCS#12 bundle path"
  )
  private var pkcs12File: String?
  @CommandArgument(
    long: "pkcs12-password",
    description: "PKCS#12 bundle password (env: OCACLI_PKCS12_PASSWORD; prompted if omitted)"
  )
  private var pkcs12Password: String?
  @CommandOption(
    short: "k",
    long: "insecure",
    description: "Disable TLS server certificate verification (cert credentials only; for testing)"
  )
  private var insecure: Bool
  @CommandArgument(
    long: "cacert",
    description: "PEM CA bundle for TLS server-cert verification"
  )
  private var caCertFile: String?
  @CommandArgument(
    long: "crl-file",
    description: "PEM CRL bundle for TLS revocation checking"
  )
  private var crlFile: String?
  @CommandOption(
    long: "check-revocation",
    description: "Enable TLS revocation checking against leaf certificate"
  )
  private var checkRevocation: Bool
  @CommandOption(
    long: "check-revocation-all",
    description: "Enable TLS revocation checking across the full chain"
  )
  private var checkRevocationAll: Bool
  @CommandArgument(short: "P", long: "path", description: "Domain socket path")
  private var path: String?
  #if canImport(Darwin)
  @CommandArgument(short: "M", long: "mach", description: "Mach port bootstrap service name")
  private var machServiceName: String?
  #endif
  @CommandOption(
    short: "a",
    long: "automatic-reconnect",
    description: "Attempt to reconnect on disconnection"
  )
  private var automaticReconnect: Bool
  @CommandOption(
    short: "r",
    long: "resolve-device-tree",
    description: "Resolve device action objects at startup"
  )
  private var resolveDeviceTree: Bool
  @CommandOption(
    short: "s",
    long: "subscribe-properties",
    description: "Subscribe to property change events"
  )
  private var cacheProperties: Bool
  @CommandArgument(short: "l", long: "log-level", description: "Log level")
  private var logLevel: String?
  @CommandOption(long: "help", description: "Show usage description")
  private var help: Bool
  @CommandFlags // Inject the flags object
  private var flags: CommandLineKit.Flags
  @CommandArgument(
    short: "t",
    long: "connection-timeout",
    description: "Connection timeout (seconds)"
  )
  private var connectionTimeout: Int?
  @CommandArgument(short: "T", long: "response-timeout", description: "Response timeout (seconds)")
  private var responseTimeout: Int?
  @CommandArgument(
    short: "B",
    long: "batch-size",
    description: "Request message batch size (bytes)"
  )
  private var batchSize: Int?
  @CommandArgument(
    long: "batch-threshold",
    description: "Request message batch threshold (milliseconds)"
  )
  private var batchThreshold: Int?

  private let lineReader = LineReader()
  private let commands = REPLCommandRegistry.shared
  private static var savedTermios: termios = {
    var term = termios()
    tcgetattr(STDIN_FILENO, &term)
    return term
  }()

  private typealias CommandTokens = [String]
  private var context: Context!
  private var commandSourceStream: AsyncStream<CommandTokens>!
  private let commandDidComplete = DispatchSemaphore(value: 0)

  init() {
    commands.register(AddMember.self)
    commands.register(AddPreSharedKey.self)
    commands.register(AddSignalPath.self)
    commands.register(ApplyParamDataSet.self)
    commands.register(ApplyParameterData.self)
    commands.register(ApplyPatch.self)
    commands.register(BeginActiveComponentUpdate.self)
    commands.register(BeginPassiveComponentUpdate.self)
    commands.register(CallMethod.self)
    commands.register(ChangePreSharedKey.self)
    commands.register(ChangePath.self)
    commands.register(ClearCache.self)
    commands.register(ClearDataset.self)
    commands.register(ClearFlag.self)
    commands.register(Connect.self)
    commands.register(ConnectionInfo.self)
    commands.register(ConstructActionObject.self)
    commands.register(ConstructDataset.self)
    commands.register(DeleteActionObject.self)
    commands.register(DeleteMember.self)
    commands.register(DeleteInputPort.self)
    commands.register(DeleteOutputPort.self)
    commands.register(DeleteInputPortClockMapEntry.self)
    commands.register(DeleteOutputPortClockMapEntry.self)
    commands.register(DeletePreSharedKey.self)
    commands.register(DeleteSignalPath.self)
    commands.register(DisableControlSecurity.self)
    commands.register(DeviceInfo.self)
    commands.register(Disconnect.self)
    commands.register(Dump.self)
    commands.register(DumpDataset.self)
    #if DEBUG
    commands.register(DumpSparseRolePathCache.self)
    #endif
    commands.register(DuplicateDataset.self)
    commands.register(EnableControlSecurity.self)
    commands.register(EndUpdateProcess.self)
    commands.register(Exit.self)
    commands.register(FetchCurrentParameterData.self)
    commands.register(FindActionObjectsByLabelRecursive.self)
    commands.register(FindActionObjectsByRole.self)
    commands.register(FindActionObjectsByRoleRecursive.self)
    commands.register(FindDatasets.self)
    commands.register(FindDatasetsRecursive.self)
    commands.register(FirmwareImageContainerUpdate.self)
    commands.register(Flags.self)
    commands.register(Get.self)
    commands.register(GetConnectorStatus.self)
    commands.register(GetDatasetObjectsRecursive.self)
    commands.register(GetDatasetSizes.self)
    commands.register(GetGroupController.self)
    commands.register(GetInputPortName.self)
    commands.register(GetMembers.self)
    commands.register(GetOutputPortName.self)
    commands.register(GetSignalPathRecursive.self)
    commands.register(SetInputPortClockMapEntry.self)
    commands.register(SetOutputPortClockMapEntry.self)
    commands.register(GetSinkConnector.self)
    commands.register(GetSourceConnector.self)
    commands.register(GetNominalMediaClockRate.self)
    commands.register(List.self)
    commands.register(ListObjectNumbers.self)
    commands.register(LoadDataset.self)
    commands.register(LockNoReadWrite.self)
    commands.register(LockNoWrite.self)
    commands.register(PrintWorkingPath.self)
    commands.register(PushPath.self)
    commands.register(PopPath.self)
    commands.register(ResetTimeSource.self)
    commands.register(Resolve.self)
    commands.register(SetFlag.self)
    commands.register(Set.self)
    commands.register(SetInputPortName.self)
    commands.register(SetOutputPortName.self)
    commands.register(SetNominalMediaClockRate.self)
    commands.register(Show.self)
    commands.register(StartUpdateProcess.self)
    commands.register(Statistics.self)
    commands.register(StoreCurrentParamData.self)
    commands.register(Subscribe.self)
    commands.register(Unlock.self)
    commands.register(Up.self)
    commands.register(Unsubscribe.self)
    commands.register(Watch.self)
  }

  private func usage() -> Never {
    print(
      flags.usageDescription(
        usageName: TextStyle.bold.properties.apply(to: "usage:"),
        synopsis: "[<option> ...] [---] [<program> <arg> ...]",
        usageStyle: TextProperties.empty,
        optionsName: TextStyle.bold.properties.apply(to: "options:"),
        flagStyle: TextStyle.italic.properties
      ),
      terminator: ""
    )
    exit(1)
  }

  private func readCommand(_ ln: LineReader, withPrompt prompt: String) throws -> String {
    let commandLine = try ln.readLine(
      prompt: prompt,
      maxCount: 200,
      strippingNewline: true,
      promptProperties: TextProperties(.green, nil, .bold),
      readProperties: TextProperties(.blue, nil),
      parenProperties: TextProperties(.red, nil, .bold)
    )
    return commandLine
  }

  private func initContext() async throws -> Context {
    var logger = Logger(label: "com.padl.ocacli")

    #if canImport(Darwin)
    guard hostname != nil || path != nil || machServiceName != nil, !help else {
      usage()
    }
    #else
    guard hostname != nil || path != nil, !help else {
      usage()
    }
    #endif

    if let logLevel {
      guard let logLevel = Logger.Level(rawValue: logLevel) else {
        usage()
      }
      logger.logLevel = logLevel
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
    if tls, path != nil || _machServiceName != nil {
      print(
        "error: --tls cannot be combined with --path or --mach (TLS is only supported over TCP/UDP)"
      )
      throw Ocp1Error.status(.parameterError)
    }
    if !tls, caCertFile != nil || insecure {
      print("error: --cacert / --insecure require --tls")
      throw Ocp1Error.status(.parameterError)
    }
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

  private func readCommand() throws -> [String] {
    let prompt = "\(context.currentPathString)> "
    let commandLine = try readCommand(lineReader!, withPrompt: prompt)
    return commands.tokenizeCommand(commandLine)
  }

  private func executeCommand(context: Context, tokens: [String]) async throws {
    guard tokens.count > 0 else { return }
    let command = try await commands.command(
      from: tokens,
      context: context
    )
    if await context.connection.isConnected == false && command
      .isUsableWhenDisconnected == false
    {
      throw Ocp1Error.notConnected
    }
    try await command.execute(with: context)
  }

  private func commandSourceEventLoop(
    _ continuation: AsyncStream<CommandTokens>
      .Continuation
  ) throws {
    guard let lineReader else { throw Ocp1Error.invalidHandle }

    lineReader.setCompletionCallback { currentBuffer in
      let completions = self.commands
        .getCompletions(from: currentBuffer, context: self.context) ?? []
      guard !completions.isEmpty else {
        // the line reader inserts a literal tab if we return nothing at all, so ring the
        // bell ourselves and offer the line back unchanged
        fputs("\u{07}", stdout)
        fflush(stdout)
        return [currentBuffer]
      }
      return completions
    }

    var done = false
    while !done {
      do {
        commandDidComplete.wait()
        let tokens = try readCommand()
        continuation.yield(tokens)
        lineReader.addHistory(tokens.joined(separator: " "))
      } catch LineReaderError.CTRLC, LineReaderError.EOF {
        done = true
      } catch {
        context.print(error)
      }
    }
  }

  private var isBatchMode: Bool {
    !commandsToExecute.isEmpty
  }

  private func monitorConnectionState() {
    guard !context.contextFlags.contains(.automaticReconnect) else { return }
    let context = context!
    Task {
      for try await connectionState in await context.connection.connectionState {
        if connectionState == .connectionTimedOut ||
          connectionState == .connectionFailed
        {
          Self.resetTerminal()
          context.print(Ocp1Error.notConnected)
          exit(2)
        }
      }
    }
  }

  private static func resetTerminal() {
    var term = savedTermios
    tcsetattr(STDIN_FILENO, TCSADRAIN, &term)
  }

  private func initCommandSourceStream() -> AsyncStream<CommandTokens>.Continuation {
    var continuation: AsyncStream<CommandTokens>.Continuation!
    commandSourceStream = AsyncStream<CommandTokens> {
      let task = Task {
        do {
          self.context = try await self.initContext()
        } catch {
          print(error)
          exit(2)
        }
        self.monitorConnectionState()
        commandDidComplete.signal()
        for await tokens in commandSourceStream {
          do {
            try await executeCommand(context: context, tokens: tokens)
          } catch {
            context.print(error)
            if isBatchMode { try await Exit().execute(with: context) }
          }
          commandDidComplete.signal()
        }
      }
      $0.onTermination = { @Sendable _ in
        task.cancel()
      }
      continuation = $0
    }
    return continuation
  }

  private func runInteractiveMode() throws {
    let continuation = initCommandSourceStream()
    DispatchQueue(label: "com.padl.ocacli.repl", qos: .utility).sync {
      try? self.commandSourceEventLoop(continuation)
      continuation.yield([Exit.name[0]])
    }
  }

  private func runBatchMode(_ commandsToExecute: [String]) throws {
    let continuation = initCommandSourceStream()
    for commandToExecute in commandsToExecute + [Exit.name[0]] {
      let tokens = commands.tokenizeCommand(commandToExecute)
      continuation.yield(tokens)
    }
  }

  func run() throws {
    LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }
    _ = Self.savedTermios

    signal(SIGPIPE, SIG_IGN)

    if isBatchMode {
      try runBatchMode(commandsToExecute)
    } else {
      try runInteractiveMode()
    }
    dispatchMain()
  }
}
