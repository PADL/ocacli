//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

struct GetMembers: REPLCommand, REPLClassSpecificCommand {
  static let name = ["get-members"]
  static let summary = "Get group members"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaGroup.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let group = context.currentObject as! OcaGroup
    let members: [OcaRoot] = try await group.resolveMembers()
    for member in members {
      let rolePath = try await member
        .getRolePathString(flags: context.contextFlags.cachedPropertyResolutionFlags)
      context.print(rolePath)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetGroupController: REPLCommand, REPLClassSpecificCommand {
  static let name = ["get-group-controller"]
  static let summary = "Get group controller"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaGroup.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let group = context.currentObject as! OcaGroup
    let groupController: OcaRoot = try await group.resolveGroupController()
    let rolePath = try await groupController
      .getRolePathString(flags: context.contextFlags.cachedPropertyResolutionFlags)
    context.print(rolePath)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct AddMember: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["add-member"]
  static let summary = "Add group member"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaGroup.classIdentification]
  }

  @REPLCommandArgument
  var member: OcaRoot!

  init() {}

  func execute(with context: Context) async throws {
    let group = context.currentObject as! OcaGroup
    try await group.add(member: member.objectNumber)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteMember: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["delete-member"]
  static let summary = "Delete group member"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaGroup.classIdentification]
  }

  @REPLCommandArgument
  var member: OcaRoot!

  init() {}

  func execute(with context: Context) async throws {
    let group = context.currentObject as! OcaGroup
    try await group.delete(member: member.objectNumber)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
