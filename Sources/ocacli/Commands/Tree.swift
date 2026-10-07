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
import SwiftOCA

private struct ObjectTreeNode: Sendable {
  let role: String
  let className: String
  let oNo: OcaONo
  var error: String?
  var members = [ObjectTreeNode]()
}

/// Draws a tree, one line per object, each indented under its block.
private func drawObjectTree(_ node: ObjectTreeNode) -> [String] {
  func line(_ node: ObjectTreeNode, prefix: String) -> String {
    let error = node.error.map { "  (error: \($0))" } ?? ""
    return "\(prefix)+-o \(node.role)  <class \(node.className), ONo \(node.oNo.oNoString)>\(error)"
  }

  func draw(_ members: [ObjectTreeNode], prefix: String) -> [String] {
    members.enumerated().flatMap { index, member in
      let isLast = index == members.count - 1
      return [line(member, prefix: prefix)] +
        draw(member.members, prefix: prefix + (isLast ? "  " : "| "))
    }
  }

  return [line(node, prefix: "")] + draw(node.members, prefix: "  ")
}

/// The registered class name if the device's class is registered, otherwise its class ID.
private func className(of object: OcaRoot?, classID: OcaClassID) -> String {
  if let object, type(of: object).classID == classID {
    String(describing: type(of: object))
  } else {
    classID.description
  }
}

@OcaConnectionActor
private extension OcaRoot {
  func getObjectTree(classID: OcaClassID, flags: OcaPropertyResolutionFlags) async
    -> ObjectTreeNode
  {
    var role = (try? await getRole()) ?? objectNumber.oNoString
    // the root block has no role of its own
    if role.isEmpty, objectNumber == OcaRootBlockONo { role = "root" }

    var node = ObjectTreeNode(
      role: role,
      className: className(of: self, classID: classID),
      oNo: objectNumber
    )

    guard let block = self as? OcaBlock else { return node }

    let actionObjects: [OcaObjectIdentification]
    do {
      actionObjects = try await block.getActionObjects(flags: flags)
    } catch {
      node.error = String(describing: error)
      return node
    }

    node.members = await boundedConcurrentMap(actionObjects) {
      [weak connection = block.connectionDelegate, owner = block.objectNumber] member in
      do {
        guard let connection else { throw Ocp1Error.noConnectionDelegate }
        let object: OcaRoot = try await connection.resolve(object: member, owner: owner)
        return await object.getObjectTree(
          classID: member.classIdentification.classID,
          flags: flags
        )
      } catch {
        // a member we cannot resolve still has the number and class its block gave us
        return ObjectTreeNode(
          role: member.oNo.oNoString,
          className: className(of: nil, classID: member.classIdentification.classID),
          oNo: member.oNo,
          error: String(describing: error)
        )
      }
    }

    return node
  }
}

struct Tree: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["tree"]
  static let summary = "Draw the object tree under a block"
  static var supportedClasses: [OcaClassIdentification] { [OcaBlock.classIdentification] }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var object: OcaRoot!

  init() {}

  func execute(with context: Context) async throws {
    let object = object ?? context.currentObject
    // ask for the device's class, as its block would have told us for any member
    let classID = await (try? object.getClassIdentification().classID) ?? type(of: object).classID
    let tree = await object.getObjectTree(
      classID: classID,
      flags: context.contextFlags.cachedPropertyResolutionFlags
    )

    for line in drawObjectTree(tree) {
      context.print(line)
    }
  }
}
