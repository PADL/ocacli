//
// Copyright (c) 2026 PADL Software Pty Ltd
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

import Foundation
@_spi(SwiftOCAPrivate) import SwiftOCA

// AES70-2024 CM4 (OcaMediaTransportApplication / OcaMediaTransportSessionAgent) commands.

private extension OcaMediaStreamMode {
  var summary: String {
    "\(frameFormat) \(encodingType) \(Int(samplingRate)) Hz x\(channelCount)"
  }
}

private extension OcaMediaStreamEndpoint {
  func summary(status: OcaMediaStreamEndpointStatus?, adaptation: OcaAdaptationIdentifier) -> String {
    let state = status.map { "\($0.state)" } ?? "unknown"
    var line = "\(idInternal)\t\(direction)\t\(state)\t\"\(userLabel)\"\t\(currentStreamMode.summary)"
    if !idExternal.isEmpty {
      line += "\text \(OcaRemoteEndpointID.description(of: idExternal, adaptation: adaptation))"
    }
    return line
  }
}

/// The zero-based index of the argument the cursor is on.
func replArgumentIndex(_ buffer: String) -> Int {
  let (tokens, endsWithSeparator) = replTokenize(buffer)
  return max(0, tokens.count - 1 - (endsWithSeparator ? 0 : 1))
}

private extension OcaMediaTransportSessionAgent {
  func sessionCompletions() async -> [String]? {
    guard let sessions = try? await $sessions._getValue(self, flags: []) else { return nil }
    return sessions.map { String($0.idInternal) }
  }
}

private extension OcaMediaTransportApplication {
  /// Endpoint IDs, for commands taking any endpoint.
  func endpointCompletions() async -> [String]? {
    guard let endpoints = try? await $endpoints._getValue(self, flags: []) else { return nil }
    return endpoints.map { String($0.idInternal) }
  }

  /// Endpoint labels and IDs, of input endpoints only when `inputsOnly`.
  func endpointLabelCompletions(inputsOnly: Bool = false) async -> [String]? {
    guard let endpoints = try? await $endpoints._getValue(self, flags: []) else { return nil }
    let chosen = endpoints.filter { !inputsOnly || $0.direction == .input }
    return chosen.map(\.userLabel).filter { !$0.isEmpty } + chosen.map { String($0.idInternal) }
  }

  /// Input endpoint labels and IDs, for the connect and disconnect commands.
  func inputEndpointCompletions() async -> [String]? {
    await endpointLabelCompletions(inputsOnly: true)
  }

  /// The endpoint named by label or ID, an input one when `inputsOnly`.
  func endpoint(named name: String, inputsOnly: Bool = false) async throws -> OcaMediaStreamEndpoint {
    let endpoints = try await $endpoints._getValue(self, flags: [])
    guard let endpoint = endpoints.first(where: {
      (!inputsOnly || $0.direction == .input) && ($0.userLabel == name || String($0.idInternal) == name)
    }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return endpoint
  }

  /// The input endpoint named by label or ID.
  func inputEndpoint(_ name: String) async throws -> OcaMediaStreamEndpoint {
    try await endpoint(named: name, inputsOnly: true)
  }

  /// The session agent's session and connection for a local endpoint.
  func sessionConnection(
    for endpoint: OcaMediaStreamEndpoint,
    with context: Context
  ) async throws -> (OcaMediaTransportSessionAgent, OcaMediaTransportSession, OcaMediaTransportSessionConnection) {
    let agentONos = try await $transportSessionControlAgentONos._getValue(self, flags: [])
    guard let agentONo = agentONos.first else { throw Ocp1Error.status(.invalidRequest) }
    guard let agent = try await context.connection.resolve(objectOfUnknownClass: agentONo)
      as? OcaMediaTransportSessionAgent
    else {
      throw Ocp1Error.objectClassMismatch
    }
    let sessions = try await agent.$sessions._getValue(agent, flags: [])
    guard let session = sessions.first(where: {
      $0.connections.contains { $0.localEndpointID == endpoint.idInternal }
    }), let connection = session.connections.first(where: { $0.localEndpointID == endpoint.idInternal })
    else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return (agent, session, connection)
  }
}

private extension Aes67OcaMediaTransportApplication {
  /// The stream source registry's entries (AES70-21 Clause 10.3), each named by its
  /// IDExternal.
  func registeredSources(with context: Context) async throws -> [Aes67StreamEndpointDescriptor] {
    let registryONo = try await $streamSourceRegistryONo._getValue(self, flags: [])
    guard registryONo != OcaInvalidONo,
          let registry = try await context.connection.resolve(objectOfUnknownClass: registryONo)
          as? Aes67StreamEndpointRegistry
    else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return try await registry.$registry._getValue(registry, flags: [])
  }

  func registeredSourceNames(with context: Context) async -> [String]? {
    guard let sources = try? await registeredSources(with: context) else { return nil }
    return sources.compactMap { String(bytes: $0.idExternal, encoding: .utf8) }.filter { !$0.isEmpty }
  }

  /// A registry entry with an SDP, by its IDExternal; its MediaIDType and MediaID name its
  /// stream.
  func registeredSource(
    named name: String,
    with context: Context
  ) async throws -> Aes67StreamEndpointDescriptor {
    let sources = try await registeredSources(with: context)
    guard let source = sources.first(where: { String(bytes: $0.idExternal, encoding: .utf8) == name }),
          !source.sdpString.isEmpty
    else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return source
  }
}

private extension DanteOcaMediaTransportApplication {
  /// The channel endpoint carrying the same external ID as a stream endpoint.
  func channelEndpointID(for endpoint: OcaMediaStreamEndpoint) async throws -> OcaID16 {
    let channelEndpoints = try await $channelEndpoints._getValue(self, flags: [])
    guard let id = channelEndpoints.first(where: {
      $0.value.direction == .input && $0.value.idExternal == endpoint.idExternal
    })?.key else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return id
  }
}

struct GetEndpoints: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-endpoints", "endpoints"]
  static let summary = "List media stream endpoints with their status"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var id: Int?

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let statuses = try await application.$endpointStatuses._getValue(application, flags: [])
    let adaptation = try await application.$adaptationIdentifier._getValue(application, flags: [])
    if let id {
      let endpoint = try await application.getEndpoint(id: OcaMediaStreamEndpointID(id))
      context.print(endpoint.summary(status: statuses[endpoint.idInternal], adaptation: adaptation))
      context.print("\(endpoint)")
    } else {
      let endpoints = try await application.$endpoints._getValue(application, flags: [])
      for endpoint in endpoints {
        context.print(endpoint.summary(status: statuses[endpoint.idInternal], adaptation: adaptation))
      }
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportApplication)?.endpointCompletions()
  }
}

struct GetEndpointCounters: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["get-endpoint-counters"]
  static let summary = "Show the counters of a media stream endpoint"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  @REPLCommandArgument
  var id: Int!

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let counterSet = try await application.getEndpointCounterSet(endpointID: OcaMediaStreamEndpointID(id))
    for line in await CounterSetDescriber(context: context).describe(counterSet) {
      context.print(line)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportApplication)?.endpointCompletions()
  }
}

struct AttachEndpointCounterNotifier: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["attach-endpoint-counter-notifier"]
  static let summary = "Attach a counter notifier to an endpoint's counter: <endpoint ID> <counter ID> <notifier>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  @REPLCommandArgument
  var id: Int!

  @REPLCommandArgument
  var counterID: Int!

  @REPLCommandArgument
  var notifier: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    try await application.attachEndpointCounterNotifier(
      endpointID: OcaMediaStreamEndpointID(id),
      counterID: parseCounterID(counterID),
      notifierONo: notifier
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    switch replArgumentIndex(currentBuffer) {
    case 0: await (context.currentObject as? OcaMediaTransportApplication)?.endpointCompletions()
    case 2: await context.resolveCompletions(forPartialRolePath: currentBuffer.replFinalWord)
    default: nil
    }
  }
}

struct DetachEndpointCounterNotifier: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["detach-endpoint-counter-notifier"]
  static let summary = "Detach a counter notifier from an endpoint's counter: <endpoint ID> <counter ID> <notifier>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  @REPLCommandArgument
  var id: Int!

  @REPLCommandArgument
  var counterID: Int!

  @REPLCommandArgument
  var notifier: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    try await application.detachEndpointCounterNotifier(
      endpointID: OcaMediaStreamEndpointID(id),
      counterID: parseCounterID(counterID),
      notifierONo: notifier
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    switch replArgumentIndex(currentBuffer) {
    case 0: await (context.currentObject as? OcaMediaTransportApplication)?.endpointCompletions()
    case 2: await context.resolveCompletions(forPartialRolePath: currentBuffer.replFinalWord)
    default: nil
    }
  }
}

struct ResetEndpointCounters: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["reset-endpoint-counters"]
  static let summary = "Reset endpoint counters, 0 meaning every endpoint: <endpoint ID|0> [counter ID]"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var id: Int!

  @REPLCommandArgument
  var counterID: Int?

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    // a counter ID of zero resets the whole set
    try await application.resetEndpointCounterSet(
      endpointID: OcaMediaStreamEndpointID(id),
      counterID: counterID.map(parseCounterID) ?? 0
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    guard replArgumentIndex(currentBuffer) == 0 else { return nil }
    return await (context.currentObject as? OcaMediaTransportApplication)?.endpointCompletions()
  }
}

struct GetSessions: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-sessions", "sessions"]
  static let summary = "List media transport sessions with their status"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportSessionAgent.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var id: Int?

  init() {}

  func execute(with context: Context) async throws {
    let agent = context.currentObject as! OcaMediaTransportSessionAgent
    let statuses = try await agent.$sessionStatuses._getValue(agent, flags: [])
    let sessionType = try await agent.$sessionType._getValue(agent, flags: [])
    let sessions: [OcaMediaTransportSession] = if let id {
      [try await agent.getSession(id: OcaMediaTransportSessionID(id))]
    } else {
      try await agent.$sessions._getValue(agent, flags: [])
    }
    for session in sessions {
      let status = statuses[session.idInternal]
      var line = "\(session.idInternal)\t\(status.map { "\($0.state)" } ?? "unknown")"
      line += "\tstreaming=\(session.streamingEnabled)"
      for connection in session.connections {
        line += "\tlocal=\(connection.localEndpointID)"
        if !connection.remoteEndpointID.isEmpty {
          let remote = OcaRemoteEndpointID.description(of: connection.remoteEndpointID, adaptation: sessionType)
          line += "\tremote=\(remote.isEmpty ? "unbound" : remote)"
        }
      }
      if let status, let detail = OcaSessionStatusDescription.description(
        of: status.adaptationData, sessionType: sessionType
      ) {
        line += "\t\(detail)"
      }
      context.print(line)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportSessionAgent)?.sessionCompletions()
  }
}

struct ConfigureConnection: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["configure-connection", "bind"]
  static let summary = "Configure a session's connection: <session ID> <remote endpoint ID>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportSessionAgent.classIdentification]
  }

  @REPLCommandArgument
  var sessionID: Int!

  @REPLCommandArgument
  var talker: String!

  init() {}

  func execute(with context: Context) async throws {
    let agent = context.currentObject as! OcaMediaTransportSessionAgent
    let session = try await agent.getSession(id: OcaMediaTransportSessionID(sessionID))
    guard let connection = session.connections.first else {
      throw Ocp1Error.status(.invalidRequest)
    }
    let sessionType = try await agent.$sessionType._getValue(agent, flags: [])
    try await agent.configureConnection(
      sessionID: session.idInternal,
      connectionID: connection.id,
      localEndpointID: connection.localEndpointID,
      remoteEndpointID: try OcaRemoteEndpointID.blob(parsing: talker, adaptation: sessionType)
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    guard replArgumentIndex(currentBuffer) == 0 else { return nil }
    return await (context.currentObject as? OcaMediaTransportSessionAgent)?.sessionCompletions()
  }
}

struct ResetSession: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["reset-session", "unbind"]
  static let summary = "Unbind a session from its talker"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportSessionAgent.classIdentification]
  }

  @REPLCommandArgument
  var sessionID: Int!

  init() {}

  func execute(with context: Context) async throws {
    let agent = context.currentObject as! OcaMediaTransportSessionAgent
    try await agent.resetSession(id: OcaMediaTransportSessionID(sessionID))
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportSessionAgent)?.sessionCompletions()
  }
}

struct SetStreamingEnabled: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["set-streaming-enabled"]
  static let summary = "Start or stop a session's stream: <session ID> <true|false>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportSessionAgent.classIdentification]
  }

  @REPLCommandArgument
  var sessionID: Int!

  @REPLCommandArgument
  var enabled: Bool!

  init() {}

  func execute(with context: Context) async throws {
    let agent = context.currentObject as! OcaMediaTransportSessionAgent
    try await agent.setStreamingEnabled(id: OcaMediaTransportSessionID(sessionID), active: enabled)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    switch replArgumentIndex(currentBuffer) {
    case 0: await (context.currentObject as? OcaMediaTransportSessionAgent)?.sessionCompletions()
    case 1: ["true", "false"]
    default: nil
    }
  }
}

/// Connects an input endpoint, found by label or ID, to a remote endpoint: through the
/// session agent for stream-based adaptations, through the channel endpoints for
/// channel-based ones (AES70-23). An AES67 endpoint is configured from SDP, a registry
/// entry's or one given verbatim, which leaves it Ready (AES70-21 Clause 10.2.4), and then
/// connected and started with ConnectAndStart (Annex D.5) unless `start` is false. A registry
/// entry's name is its IDExternal, such as `<session>/<MediaID>` for one stream of several.
struct ConnectEndpoint: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["connect-endpoint"]
  static let summary = "Connect an input endpoint: <endpoint label or ID>"
    + " <registry entry name or SDP (AES67); remote endpoint ID (other adaptations)>"
    + " [true|false: start, AES67 only] [<media ID type> <media ID>: SDP only]"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  var minimumRequiredArguments: Int { 2 }

  @REPLCommandArgument
  var endpoint: String!

  @REPLCommandArgument
  var remote: String!

  @REPLCommandArgument
  var start: Bool! = true

  @REPLCommandArgument
  var mediaIDType: String!

  @REPLCommandArgument
  var mediaID: String!

  init() {}

  /// Reads the trailing media ID arguments, which only a verbatim SDP may have: both or
  /// neither, the type named as `Aes67MediaIDType` names its cases.
  static func parseMediaID(
    type: String?,
    id: String?,
    remote: String
  ) throws -> (Aes67MediaIDType, OcaString)? {
    guard let type else { return nil }
    guard let id, remote.hasPrefix("v=0"),
          let mediaIDType = Aes67MediaIDType.value(for: type) as? Aes67MediaIDType
    else {
      throw REPLCommandRegistry.UsageError(summary: summary)
    }
    return (mediaIDType, id)
  }

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let start = start ?? true
    let media = try Self.parseMediaID(type: mediaIDType, id: mediaID, remote: remote)
    guard application is Aes67OcaMediaTransportApplication || (start && media == nil) else {
      // only AES70-21 configures an endpoint from SDP without starting it
      throw REPLCommandRegistry.UsageError(summary: Self.summary)
    }
    let target = try await application.inputEndpoint(endpoint)
    if let application = application as? DanteOcaMediaTransportApplication {
      let id = try await application.channelEndpointID(for: target)
      try await application.subscribe(channelEndpoint: id, to: remote)
      context.print("subscribed channel endpoint \(id) \"\(target.userLabel)\" to \(remote!)")
      return
    }
    if let application = application as? Aes67OcaMediaTransportApplication {
      try await configure(application, target: target, media: media, start: start, with: context)
      return
    }
    let adaptation = try await application.$adaptationIdentifier._getValue(application, flags: [])
    let (agent, session, connection) = try await application.sessionConnection(for: target, with: context)
    try await agent.configureConnection(
      sessionID: session.idInternal,
      connectionID: connection.id,
      localEndpointID: connection.localEndpointID,
      remoteEndpointID: try OcaRemoteEndpointID.blob(parsing: remote, adaptation: adaptation)
    )
    context.print("connected endpoint \(target.idInternal) \"\(target.userLabel)\" (session \(session.idInternal)) to \(remote!)")
  }

  /// AES70-21 connects by SDP: given verbatim, with the media ID arguments when it has several
  /// streams, or a registry entry's, with the MediaIDType and MediaID that name its stream.
  private func configure(
    _ application: Aes67OcaMediaTransportApplication,
    target: OcaMediaStreamEndpoint,
    media: (Aes67MediaIDType, OcaString)?,
    start: Bool,
    with context: Context
  ) async throws {
    if remote.hasPrefix("v=0") {
      try await application.configureEndpointFromSDP(
        endpointID: target.idInternal,
        sdpString: remote,
        mediaIDType: media?.0 ?? .none,
        mediaID: media?.1 ?? ""
      )
    } else {
      let source = try await application.registeredSource(named: remote, with: context)
      try await application.configureEndpointFromSDP(
        endpointID: target.idInternal,
        sdpString: source.sdpString,
        mediaIDType: source.mediaIDType,
        mediaID: source.mediaID
      )
    }
    context.print("configured endpoint \(target.idInternal) \"\(target.userLabel)\" from SDP, Ready")
    guard start else { return }
    do {
      try await application.applyEndpointCommand(endpointID: target.idInternal, command: .connectAndStart)
    } catch {
      throw StartFailed(endpointID: target.idInternal, underlying: error)
    }
    context.print("connected and started endpoint \(target.idInternal) \"\(target.userLabel)\"")
  }

  /// A configure that succeeded followed by a start that did not.
  struct StartFailed: Error, CustomStringConvertible, LocalizedError {
    let endpointID: OcaMediaStreamEndpointID
    let underlying: any Error
    var description: String {
      let reason = if case let Ocp1Error.status(status) = underlying { "\(status)" } else { "\(underlying)" }
      return "endpoint \(endpointID) configured, Ready; start failed: \(reason)"
    }
    var errorDescription: String? { description }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    guard let application = context.currentObject as? OcaMediaTransportApplication else { return nil }
    let aes67 = application as? Aes67OcaMediaTransportApplication
    switch replArgumentIndex(currentBuffer) {
    case 0: return await application.inputEndpointCompletions()
    case 1: return await aes67?.registeredSourceNames(with: context)
    case 2: return aes67 != nil ? ["true", "false"] : nil
    case 3: return aes67 != nil ? Aes67MediaIDType.allCases.map { String(describing: $0) } : nil
    default: return nil
    }
  }
}

struct DisconnectEndpoint: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["disconnect-endpoint"]
  static let summary = "Disconnect an input endpoint from its remote: <endpoint label or ID>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  @REPLCommandArgument
  var endpoint: String!

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let target = try await application.inputEndpoint(endpoint)
    if let application = application as? DanteOcaMediaTransportApplication {
      try await application.clearChannelEndpoint(id: try await application.channelEndpointID(for: target))
      return
    }
    if let application = application as? Aes67OcaMediaTransportApplication {
      // an empty SDP closes the connection: NotReady (AES70-21 Clause 10.2.4)
      try await application.configureEndpointFromSDP(endpointID: target.idInternal, sdpString: "")
      return
    }
    let (agent, session, _) = try await application.sessionConnection(for: target, with: context)
    try await agent.resetSession(id: session.idInternal)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportApplication)?.inputEndpointCompletions()
  }
}

/// Applies an AES70 endpoint command (OcaMediaStreamEndpointCommand) to an endpoint of
/// either direction, found by label or ID: `connectAndStart` starts one ConfigureEndpointFromSDP
/// has left Ready (AES70-21 Annex D.5).
struct ApplyEndpointCommand: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["apply-endpoint-command"]
  static let summary = "Apply a command to an endpoint: <endpoint label or ID> <command>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  /// The command names, as `OcaMediaStreamEndpointCommand` names its cases.
  static var commandNames: [String] {
    OcaMediaStreamEndpointCommand.allCases.map { String(describing: $0) }
  }

  @REPLCommandArgument
  var endpoint: String!

  @REPLCommandArgument
  var command: String!

  init() {}

  /// The command `name` names, one of `commandNames`.
  static func parseCommand(_ name: String) throws -> OcaMediaStreamEndpointCommand {
    guard let command = OcaMediaStreamEndpointCommand.value(for: name) as? OcaMediaStreamEndpointCommand
    else {
      let names = commandNames.joined(separator: "|")
      throw REPLCommandRegistry.UsageError(summary: "\(summary), <command> one of \(names)")
    }
    return command
  }

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let endpointCommand = try Self.parseCommand(command)
    let target = try await application.endpoint(named: endpoint)
    try await application.applyEndpointCommand(endpointID: target.idInternal, command: endpointCommand)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    switch replArgumentIndex(currentBuffer) {
    case 0: await (context.currentObject as? OcaMediaTransportApplication)?.endpointLabelCompletions()
    case 1: commandNames
    default: nil
    }
  }
}
