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

private func hex(_ blob: OcaBlob) -> String {
  blob.map { String($0, radix: 16).leftPadded(2) }.joined()
}

private extension String {
  func leftPadded(_ width: Int) -> String {
    count >= width ? self : String(repeating: "0", count: width - count) + self
  }
}

private extension OcaMediaStreamMode {
  var summary: String {
    "\(frameFormat) \(encodingType) \(Int(samplingRate)) Hz x\(channelCount)"
  }
}

private extension OcaMediaStreamEndpoint {
  func summary(status: OcaMediaStreamEndpointStatus?) -> String {
    let state = status.map { "\($0.state)" } ?? "unknown"
    var line = "\(idInternal)\t\(direction)\t\(state)\t\"\(userLabel)\"\t\(currentStreamMode.summary)"
    if let external = try? idExternal.decode(MilanMediaStreamEndpointIDExternal.self),
       idExternal.count == 10
    {
      line += "\tmilan \(String(external.entityID, radix: 16)):\(external.streamIndex)"
    } else if !idExternal.isEmpty {
      line += "\text \(hex(idExternal))"
    }
    return line
  }
}

/// Parses "<entityID>:<streamIndex>" (entity ID in hex) into a Milan external endpoint ID.
private func milanEndpointID(_ string: String) throws -> MilanMediaStreamEndpointIDExternal {
  let parts = string.split(separator: ":", maxSplits: 1)
  guard parts.count == 2,
        let entityID = UInt64(parts[0].replacingOccurrences(of: "0x", with: ""), radix: 16),
        let streamIndex = UInt16(parts[1])
  else {
    throw Ocp1Error.status(.parameterError)
  }
  return MilanMediaStreamEndpointIDExternal(entityID: entityID, streamIndex: streamIndex)
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
    if let id {
      let endpoint = try await application.getEndpoint(OcaMediaStreamEndpointID(id))
      context.print(endpoint.summary(status: statuses[endpoint.idInternal]))
      context.print("\(endpoint)")
    } else {
      let endpoints = try await application.$endpoints._getValue(application, flags: [])
      for endpoint in endpoints {
        context.print(endpoint.summary(status: statuses[endpoint.idInternal]))
      }
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
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
        if let remote = try? connection.remoteEndpointID.decode(MilanMediaStreamEndpointIDExternal.self),
           connection.remoteEndpointID.count == 10
        {
          line += remote == .unbound
            ? "\tremote=unbound"
            : "\tremote=\(String(remote.entityID, radix: 16)):\(remote.streamIndex)"
        } else if !connection.remoteEndpointID.isEmpty {
          line += "\tremote=\(hex(connection.remoteEndpointID))"
        }
      }
      if let status, !status.adaptationData.isEmpty,
         let milan = try? status.adaptationData.decode(MilanSessionStatusAdaptationData.self)
      {
        line += "\t\(milan.substate)"
        if milan.srpFailureCode != 0 { line += " srp=\(milan.srpFailureCode)" }
        if milan.msrpAccumulatedLatency != 0 { line += " latency=\(milan.msrpAccumulatedLatency)ns" }
      }
      context.print(line)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}

struct ConfigureConnection: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["configure-connection", "bind"]
  static let summary = "Bind a session to a talker: <session ID> <entityID>:<stream index>"

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
    try await agent.configureConnection(
      sessionID: session.idInternal,
      connectionID: connection.id,
      localEndpointID: connection.localEndpointID,
      remoteEndpointID: try milanEndpointID(talker).blob
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}

/// Binds an input endpoint, found by label or ID, through the application's session agent.
struct PatchStream: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["patch-stream"]
  static let summary = "Bind an input endpoint by label or ID: <endpoint> <entityID>:<stream index>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportApplication.classIdentification]
  }

  @REPLCommandArgument
  var endpoint: String!

  @REPLCommandArgument
  var talker: String!

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! OcaMediaTransportApplication
    let endpoints = try await application.$endpoints._getValue(application, flags: [])
    guard let target = endpoints.first(where: {
      $0.direction == .input && ($0.userLabel == endpoint || String($0.idInternal) == endpoint)
    }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    let agentONos = try await application.$transportSessionControlAgentONos
      ._getValue(application, flags: [])
    guard let agentONo = agentONos.first else { throw Ocp1Error.status(.invalidRequest) }
    guard let agent = try await context.connection.resolve(objectOfUnknownClass: agentONo)
      as? OcaMediaTransportSessionAgent
    else {
      throw Ocp1Error.objectClassMismatch
    }
    let sessions = try await agent.$sessions._getValue(agent, flags: [])
    guard let session = sessions.first(where: {
      $0.connections.contains { $0.localEndpointID == target.idInternal }
    }), let connection = session.connections.first(where: { $0.localEndpointID == target.idInternal })
    else {
      throw Ocp1Error.status(.invalidRequest)
    }
    try await agent.configureConnection(
      sessionID: session.idInternal,
      connectionID: connection.id,
      localEndpointID: connection.localEndpointID,
      remoteEndpointID: try milanEndpointID(talker).blob
    )
    context.print("bound endpoint \(target.idInternal) \"\(target.userLabel)\" (session \(session.idInternal)) to \(talker!)")
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}
