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

// AES70-21 Aes67StreamEndpointRegistry (stream source registry) commands. They bind to the
// registry object, so they apply to any adaptation that instantiates one.

private extension Aes67StreamEndpointDescriptor {
  var name: String { String(bytes: idExternal, encoding: .utf8) ?? "" }

  var summary: String {
    var line = "\"\(name)\"\t\(direction)\t\(streamCastMode)\t\(streamMode.frameFormat) " +
      "\(streamMode.encodingType) \(Int(streamMode.samplingRate)) Hz x\(streamMode.channelCount)"
    if let address = addresses.first {
      line += "\t\(address.ipAddress):\(address.port)"
    }
    if let source = String(bytes: infoSource, encoding: .utf8), !source.isEmpty {
      line += "\t\(source)"
    }
    return line
  }
}

extension Aes67StreamTransportAddress.IPAddress: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .ip4(address): address
    case let .ip6(address): "[\(address)]"
    }
  }
}

private extension Aes67StreamEndpointRegistry {
  func entryNameCompletions() async -> [String]? {
    guard let entries = try? await $registry._getValue(self, flags: []) else { return nil }
    return entries.map(\.name).filter { !$0.isEmpty }
  }
}

struct GetRegistry: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["get-registry", "get-stream-sources", "stream-sources"]
  static let summary = "List the stream endpoint registry"

  static var supportedClasses: [OcaClassIdentification] {
    [Aes67StreamEndpointRegistry.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let registry = context.currentObject as! Aes67StreamEndpointRegistry
    for entry in try await registry.$registry._getValue(registry, flags: []) {
      context.print(entry.summary)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}

struct GetRegistryEntry: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["get-registry-entry", "registry-entry"]
  static let summary = "Show a registry entry and its SDP: <session name>"

  static var supportedClasses: [OcaClassIdentification] {
    [Aes67StreamEndpointRegistry.classIdentification]
  }

  @REPLCommandArgument
  var name: String!

  init() {}

  func execute(with context: Context) async throws {
    let registry = context.currentObject as! Aes67StreamEndpointRegistry
    let entry = try await registry.getRegistryEntry(idExternal: OcaBlob(Array(name.utf8)))
    context.print(entry.summary)
    if let data = try? entry.adaptationData.content {
      context.print("\(data)")
    }
    if !entry.sdpString.isEmpty {
      context.print(entry.sdpString)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? Aes67StreamEndpointRegistry)?.entryNameCompletions()
  }
}

struct DeleteRegistryEntry: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["delete-registry-entry"]
  static let summary = "Delete a registry entry: <session name>"

  static var supportedClasses: [OcaClassIdentification] {
    [Aes67StreamEndpointRegistry.classIdentification]
  }

  @REPLCommandArgument
  var name: String!

  init() {}

  func execute(with context: Context) async throws {
    let registry = context.currentObject as! Aes67StreamEndpointRegistry
    try await registry.deleteRegistryEntry(idExternal: OcaBlob(Array(name.utf8)))
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await (context.currentObject as? Aes67StreamEndpointRegistry)?.entryNameCompletions()
  }
}

struct AddRegistryEntriesFromSDP: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["add-registry-entries-from-sdp"]
  static let summary = "Have the device add registry entries from an SDP: <SDP text or @file>"

  static var supportedClasses: [OcaClassIdentification] {
    [Aes67StreamEndpointRegistry.classIdentification]
  }

  @REPLCommandArgument
  var sdp: String!

  init() {}

  func execute(with context: Context) async throws {
    let registry = context.currentObject as! Aes67StreamEndpointRegistry
    let sdpString = if sdp.hasPrefix("@") {
      try String(contentsOfFile: String(sdp.dropFirst()), encoding: .utf8)
    } else {
      sdp!
    }
    try await registry.addRegistryEntriesFromSDP(sdpString: sdpString)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}
