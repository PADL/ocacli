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
import SwiftOCA

struct CallMethod: REPLCommand {
  static let name = ["call-method"]
  static let summary = "Call an arbitrary method on the current object"

  @REPLCommandArgument
  var methodID: String!

  // TODO: add support for arguments

  init() {}

  func execute(with context: Context) async throws {
    let methodID = try OcaMethodID(unsafeString: methodID)
    let response = try await context.currentObject.sendCommandRrq(
      methodID: methodID,
      parameterCount: 0,
      parameterData: .init()
    )
    guard response.statusCode == .ok else {
      throw Ocp1Error.status(response.statusCode)
    }
    if !response.parameters.parameterData.isEmpty {
      print("0x\(response.parameters.parameterData.hexString)")
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
    nil
  }
}
