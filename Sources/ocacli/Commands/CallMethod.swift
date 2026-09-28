//
// Copyright (c) 2025 PADL Software Pty Ltd
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

struct CallMethod: REPLCommand, REPLOptionalArguments {
  static let name = ["call-method"]
  static let summary = "Call an arbitrary method on the current object"

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var methodID: String!

  /// hex-encoded OCP.1 parameters (`0x0100`), or an OCP.2 `Parameters` object
  /// (`{"Value":true}`) or bare value (`true`) for a single-parameter method, according to the
  /// protocol the connection speaks
  @REPLCommandArgument
  var parameters: String?

  init() {}

  func execute(with context: Context) async throws {
    let methodID = try OcaMethodID(unsafeString: methodID)
    let response = try await context.currentObject.sendCommandRrq(
      methodID: methodID,
      parameters: encodedParameters(methodID: methodID, with: context)
    )
    guard response.statusCode == .ok else {
      throw Ocp1Error.status(response.statusCode)
    }
    guard !response.parameters.isEmpty else { return }
    if let object = response.parameters.ocp2Parameters {
      let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
      )
      print(String(decoding: data, as: UTF8.self))
    } else {
      print("0x\(response.parameters.parameterData.hexString)")
    }
  }

  private func encodedParameters(
    methodID: OcaMethodID,
    with context: Context
  ) throws -> OcaParameters {
    guard let parameters else { return OcaParameters() }

    switch context.connection.controlProtocol {
    case .ocp1:
      // the payload goes as a single parameter, so a device that checks the count answers
      // a multi-parameter method with ParameterOutOfRange; OCP.2 has no such count
      return try OcaParameters(
        parameterCount: 1,
        parameterData: Data(fromHexEncodedString: parameters)
      )
    case .ocp2:
      let json = try JSONSerialization.jsonObject(
        with: Data(parameters.utf8),
        options: .fragmentsAllowed
      )
      if let object = json as? [String: Any] {
        return OcaParameters(ocp2Parameters: object)
      }
      // a bare value (`false`, `0`, `"name"`) is the method's single parameter
      let name = ocp2SetterParameterName(methodID: methodID, object: context.currentObject)
      return OcaParameters(ocp2Parameters: [name ?? "Value": json])
    }
  }

  /// The OCP.2 parameter name of the property whose setter is `methodID`, if there is one;
  /// otherwise the device takes a lone parameter as `Value`.
  private func ocp2SetterParameterName(methodID: OcaMethodID, object: OcaRoot) -> String? {
    for keyPath in object.allPropertyKeyPathsUncached.values {
      guard let property = object[keyPath: keyPath] as? any OcaPropertySubjectRepresentable,
            property.setMethodID == methodID
      else { continue }
      return property._ocp2SetName(object)
    }
    return nil
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}
