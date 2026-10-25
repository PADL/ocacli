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
  static let summary =
    "Call a method on the current object: <methodID> [--parameter-count N] [parameter ...]"

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var methodID: String!

  /// OCP.1: one hex argument per parameter, without a count byte (`0x03`, not `0x0103`); the
  /// parameter count is the number of arguments, or `--parameter-count N` when one argument
  /// holds N parameters already concatenated. OCP.2: a single `Parameters` object
  /// (`{"Value":true}`) or bare value (`true`) for a single-parameter method.
  @REPLCommandArgument
  var parameters: [String]?

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
    var arguments = parameters ?? []
    var parameterCount: OcaUint8?

    if arguments.first == "--parameter-count" {
      guard arguments.count >= 2, let count = OcaUint8(arguments[1]) else {
        throw REPLCommandRegistry.UsageError(summary: Self.summary)
      }
      parameterCount = count
      arguments.removeFirst(2)
    }

    switch context.connection.controlProtocol {
    case .ocp1:
      guard !arguments.isEmpty || parameterCount != nil else { return OcaParameters() }
      guard arguments.count <= Int(OcaUint8.max) else {
        throw REPLCommandRegistry.UsageError(summary: Self.summary)
      }
      // on the wire: the count, then the parameters' encodings concatenated
      var parameterData = Data()
      for argument in arguments {
        try parameterData.append(Data(fromHexEncodedString: argument))
      }
      return OcaParameters(
        parameterCount: parameterCount ?? OcaUint8(arguments.count),
        parameterData: parameterData
      )
    case .ocp2:
      // OCP.2 parameters are named, so they all go in one JSON object
      guard parameterCount == nil, arguments.count <= 1 else {
        throw REPLCommandRegistry.UsageError(
          summary: "\(Self.summary) (OCP.2 takes one Parameters object or bare value)"
        )
      }
      guard let argument = arguments.first else { return OcaParameters() }
      let json = try JSONSerialization.jsonObject(
        with: Data(argument.utf8),
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
