//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
@_spi(SwiftOCAPrivate) import SwiftOCA

/// AES70-23 channel-based routing: a Dante subscription is installed with
/// SetChannelEndpoint on a receive channel endpoint, naming the transmit channel.

private extension OcaChannelEndpoint {
  func summary(id: OcaID16) -> String {
    let name = String(bytes: idExternal, encoding: .utf8) ?? ""
    var line = "\(id)\t\(direction)\t\(connectionState)\t\"\(name)\""
    if let data = try? adaptationData.decode(DanteChannelEndpointAdaptationData.self) {
      if !data.remoteAddress.description.isEmpty {
        line += "\tremote=\(data.remoteAddress.description)\t\(data.subscriptionStatus)"
      }
      line += "\t\(data.mediaProtocol)"
    }
    return line
  }
}

struct GetChannelEndpoints: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-channel-endpoints", "channel-endpoints"]
  static let summary = "List Dante channel endpoints with their connection state"

  static var supportedClasses: [OcaClassIdentification] {
    [DanteOcaMediaTransportApplication.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var id: Int?

  init() {}

  func execute(with context: Context) async throws {
    let application = context.currentObject as! DanteOcaMediaTransportApplication
    if let id {
      let endpoint = try await application.getChannelEndpoint(OcaID16(id))
      context.print(endpoint.summary(id: OcaID16(id)))
      context.print("\(endpoint)")
    } else {
      let endpoints = try await application.$channelEndpoints._getValue(application, flags: [])
      for (id, endpoint) in endpoints.sorted(by: { $0.key < $1.key }) {
        context.print(endpoint.summary(id: id))
      }
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}


/// AES70-21 stream source registry listing.
struct GetStreamSources: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["get-stream-sources", "stream-sources"]
  static let summary = "List the stream source registry"

  static var supportedClasses: [OcaClassIdentification] {
    [Aes67StreamSourceListAgent.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let registry = context.currentObject as! Aes67StreamSourceListAgent
    let sources = try await registry.$streamSources._getValue(registry, flags: [])
    for source in sources {
      let name = String(bytes: source.idExternal, encoding: .utf8) ?? ""
      var line = "\"\(name)\"\t\(source.streamCastMode)\t\(source.streamMode.frameFormat) \(source.streamMode.encodingType) \(Int(source.streamMode.samplingRate)) Hz x\(source.streamMode.channelCount)"
      if let data = try? source.adaptationData.decode(Aes67EndpointAdaptationData.self),
         let ip = data.ipParameters.first
      {
        line += "\t\(ip.destinationAddress):\(ip.destinationPort)"
      }
      context.print(line)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}
