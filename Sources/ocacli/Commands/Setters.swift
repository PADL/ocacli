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
import SwiftOCA

struct Set: REPLCommand {
  static let name = ["set"]
  static let summary = "Set a property"

  @REPLCommandArgument
  var propertyName: String!

  @REPLCommandArgument
  var propertyValue: String!

  init() {}

  func execute(with context: Context) async throws {
    guard let keyPath = await context.currentObject.propertyKeyPath(for: propertyName) else {
      throw Ocp1Error.status(.parameterError)
    }

    try await context.currentObject.setValueReplString(
      context: context,
      keyPath: keyPath,
      propertyValue
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
    context.currentObject.allPropertyKeyPathsUncached.map(\.key)
  }
}
