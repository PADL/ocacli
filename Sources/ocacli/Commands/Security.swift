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

struct EnableControlSecurity: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["enable-control-security"]
  static let summary = "Enable control security"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaSecurityManager.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let timeSource = context.currentObject as! OcaSecurityManager
    try await timeSource.enableControlSecurity()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DisableControlSecurity: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["disable-control-security"]
  static let summary = "Disable control security"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaSecurityManager.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let timeSource = context.currentObject as! OcaSecurityManager
    try await timeSource.disableControlSecurity()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct AddPreSharedKey: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["add-psk"]
  static let summary = "Add pre-shared key"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaSecurityManager.classIdentification]
  }

  @REPLCommandArgument
  var identity: OcaString!

  @REPLCommandArgument
  var hexKey: OcaString!

  init() {}

  func execute(with context: Context) async throws {
    let securityManager = context.currentObject as! OcaSecurityManager
    guard let key = Data(hex: hexKey) else { throw Ocp1Error.status(.badFormat) }
    try await securityManager.addPreSharedKey(identity: identity, key: LengthTaggedData(key))
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ChangePreSharedKey: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["change-psk"]
  static let summary = "Change pre-shared key"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaSecurityManager.classIdentification]
  }

  @REPLCommandArgument
  var identity: OcaString!

  @REPLCommandArgument
  var hexKey: OcaString!

  init() {}

  func execute(with context: Context) async throws {
    let securityManager = context.currentObject as! OcaSecurityManager
    guard let key = Data(hex: hexKey) else { throw Ocp1Error.status(.badFormat) }
    try await securityManager.changePreSharedKey(identity: identity, key: LengthTaggedData(key))
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeletePreSharedKey: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["delete-psk"]
  static let summary = "Delete pre-shared key"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaSecurityManager.classIdentification]
  }

  @REPLCommandArgument
  var identity: OcaString!

  init() {}

  func execute(with context: Context) async throws {
    let securityManager = context.currentObject as! OcaSecurityManager
    try await securityManager.deletePreSharedKey(identity: identity)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
