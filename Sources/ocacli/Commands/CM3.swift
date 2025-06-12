//
// Copyright (c) 2024 PADL Software Pty Ltd
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

struct GetSourceConnector: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-source-connector"]
  static let summary = "Get media transport network source connector(s)"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportNetwork.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var id: Int?

  init() {}

  func execute(with context: Context) async throws {
    let mediaTransportNetwork = context.currentObject as! OcaMediaTransportNetwork
    if let id {
      guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
      let sourceConnector = try await mediaTransportNetwork.getSourceConnector(id)
      context.print("\(sourceConnector)")
    } else {
      let sourceConnectors = try await mediaTransportNetwork.getSourceConnectors()
      context.print("\(sourceConnectors)")
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetSinkConnector: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-sink-connector"]
  static let summary = "Get media transport network sink connector(s)"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportNetwork.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var id: Int?

  init() {}

  func execute(with context: Context) async throws {
    let mediaTransportNetwork = context.currentObject as! OcaMediaTransportNetwork
    if let id {
      guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
      let sinkConnector = try await mediaTransportNetwork.getSinkConnector(id)
      context.print("\(sinkConnector)")
    } else {
      let sinkConnectors = try await mediaTransportNetwork.getSinkConnectors()
      context.print("\(sinkConnectors)")
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetConnectorStatus: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-connector-status"]
  static let summary = "Get media transport network connector status"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaTransportNetwork.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var id: Int?

  init() {}

  func execute(with context: Context) async throws {
    let mediaTransportNetwork = context.currentObject as! OcaMediaTransportNetwork
    if let id {
      guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
      let connectorStatus = try await mediaTransportNetwork.getConnectorStatus(id)
      context.print("\(connectorStatus)")
    } else {
      let connectorStatuses = try await mediaTransportNetwork.getConnectorsStatuses()
      context.print("\(connectorStatuses)")
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetNominalMediaClockRate: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-media-clock-rate"]
  static let summary = "Get nominal media clock rate"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaClock3.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  func execute(with context: Context) async throws {
    let mediaClock3 = context.currentObject as! OcaMediaClock3

    let (nominalRate, _) = try await mediaClock3.getCurrentRate()
    print("\(nominalRate)")
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetNominalMediaClockRate: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["set-media-clock-rate"]
  static let summary = "set nominal media clock rate"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaMediaClock3.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var nominalRate: OcaFloat32!

  @REPLCommandArgument
  var timeSourceONo: OcaONo?

  func execute(with context: Context) async throws {
    let mediaClock3 = context.currentObject as! OcaMediaClock3
    let mediaClockRate = OcaMediaClockRate(nominalRate: nominalRate)

    if let timeSourceONo {
      try await mediaClock3.set(currentRate: mediaClockRate, timeSourceONo: timeSourceONo)
    } else {
      let (_, timeSourceONo) = try await mediaClock3.getCurrentRate()
      try await mediaClock3.set(currentRate: mediaClockRate, timeSourceONo: timeSourceONo)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
