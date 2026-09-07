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

  /// Input endpoint labels and IDs, for the connect and disconnect commands.
  func inputEndpointCompletions() async -> [String]? {
    guard let endpoints = try? await $endpoints._getValue(self, flags: []) else { return nil }
    let inputs = endpoints.filter { $0.direction == .input }
    return inputs.map(\.userLabel).filter { !$0.isEmpty } + inputs.map { String($0.idInternal) }
  }

  /// The input endpoint named by label or ID.
  func inputEndpoint(_ name: String) async throws -> OcaMediaStreamEndpoint {
    let endpoints = try await $endpoints._getValue(self, flags: [])
    guard let endpoint = endpoints.first(where: {
      $0.direction == .input && ($0.userLabel == name || String($0.idInternal) == name)
    }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return endpoint
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
  /// The SDP of a stream source registry entry, by session name.
  func registeredSources(with context: Context) async throws -> [Aes67StreamSourceDescriptor] {
    let registryONo = try await $streamSourceRegistryONo._getValue(self, flags: [])
    guard registryONo != OcaInvalidONo,
          let registry = try await context.connection.resolve(objectOfUnknownClass: registryONo)
          as? Aes67StreamSourceListAgent
    else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return try await registry.$streamSources._getValue(registry, flags: [])
  }

  func registeredSourceNames(with context: Context) async -> [String]? {
    guard let sources = try? await registeredSources(with: context) else { return nil }
    return sources.compactMap { String(bytes: $0.idExternal, encoding: .utf8) }.filter { !$0.isEmpty }
  }

  func registeredSDP(named name: String, with context: Context) async throws -> String {
    let sources = try await registeredSources(with: context)
    guard let source = sources.first(where: { String(bytes: $0.idExternal, encoding: .utf8) == name }),
          !source.sdpString.isEmpty
    else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return source.sdpString
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
      let endpoint = try await application.getEndpoint(OcaMediaStreamEndpointID(id))
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
    let counterSet = try await application.getEndpointCounterSet(OcaMediaStreamEndpointID(id))
    for counter in counterSet.counter {
      context.print("\(counter.id)\t\(counter.role)\t\(counter.value)")
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportApplication)?.endpointCompletions()
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
      [try await agent.getSession(OcaMediaTransportSessionID(id))]
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
    let session = try await agent.getSession(OcaMediaTransportSessionID(sessionID))
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
    try await agent.reset(session: OcaMediaTransportSessionID(sessionID))
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
    try await agent.set(session: OcaMediaTransportSessionID(sessionID), streamingEnabled: enabled)
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
/// channel-based ones (AES70-23).
struct ConnectEndpoint: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["connect-endpoint"]
  static let summary = "Connect an input endpoint to a remote: <endpoint label or ID> <remote endpoint ID>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  @REPLCommandArgument
  var endpoint: String!

  @REPLCommandArgument
  var remote: String!

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let target = try await application.inputEndpoint(endpoint)
    if let application = application as? DanteOcaMediaTransportApplication {
      let id = try await application.channelEndpointID(for: target)
      try await application.subscribe(channelEndpoint: id, to: remote)
      context.print("subscribed channel endpoint \(id) \"\(target.userLabel)\" to \(remote!)")
      return
    }
    if let application = application as? Aes67OcaMediaTransportApplication {
      // AES70-21 connects by SDP: given verbatim, or looked up by name in the registry
      let sdp = remote.hasPrefix("v=0") ? remote! : try await application.registeredSDP(named: remote, with: context)
      try await application.submitSDP(target.idInternal, sdp: sdp)
      context.print("submitted SDP for endpoint \(target.idInternal) \"\(target.userLabel)\"")
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

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    guard let application = context.currentObject as? OcaMediaTransportApplication else { return nil }
    switch replArgumentIndex(currentBuffer) {
    case 0: return await application.inputEndpointCompletions()
    case 1: return await (application as? Aes67OcaMediaTransportApplication)?.registeredSourceNames(with: context)
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
      try await application.clearChannelEndpoint(try await application.channelEndpointID(for: target))
      return
    }
    if let application = application as? Aes67OcaMediaTransportApplication {
      try await application.submitSDP(target.idInternal, sdp: "")
      return
    }
    let (agent, session, _) = try await application.sessionConnection(for: target, with: context)
    try await agent.reset(session: session.idInternal)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? OcaMediaTransportApplication)?.inputEndpointCompletions()
  }
}
