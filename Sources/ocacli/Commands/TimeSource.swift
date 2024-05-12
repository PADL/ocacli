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

struct ResetTimeSource: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["reset", "reset-time-source"]
  static let summary = "Reset time source"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaTimeSource.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let timeSource = context.currentObject as! OcaTimeSource
    try await timeSource.reset()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
