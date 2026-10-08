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

private extension OcaClassDescriptor {
  // the class ID's fields, to order classes by
  var fields: [Int] { classID.description.split(separator: ".").compactMap { Int($0) } }

  var summary: String {
    "\(classID)\t\(name)\tv\(classVersion)\t\(properties.count) properties, \(methods.count) methods"
  }

  var lines: [String] {
    let properties = properties.map {
      "  \($0.propertyID)\t\($0.name): \($0.typeName)\($0.isReadOnly ? " (read only)" : "")"
    }
    let methods = methods.map {
      let parameters = $0.parameters.map { "\($0.direction) \($0.name): \($0.typeName)" }.joined(separator: ", ")
      return "  \($0.methodID)\t\($0.name)(\(parameters))"
    }
    return [summary] + (properties.isEmpty ? [] : [" properties:"] + properties) +
      (methods.isEmpty ? [] : [" methods:"] + methods)
  }
}

struct GetControlClasses: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["get-control-classes", "control-classes"]
  static let summary = "List the classes of the device's objects"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaClassManager.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let classManager = context.currentObject as! OcaClassManager
    // the class manager promises no order
    for descriptor in try await classManager.getControlClasses().sorted(by: { $0.fields.lexicographicallyPrecedes($1.fields) }) {
      context.print(descriptor.summary)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}

struct GetControlClass: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-control-class", "control-class"]
  static let summary = "Describe a class of the device's objects, with its ancestors' elements: <class ID> [own]"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaClassManager.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var classID: String!

  /// `own` leaves out what the class inherits.
  @REPLCommandArgument
  var scope: String?

  init() {}

  func execute(with context: Context) async throws {
    let classManager = context.currentObject as! OcaClassManager
    let classID = try OcaClassID(unsafeString: classID)
    let descriptor = try await classManager.getControlClass(
      classID: classID, includeInherited: scope != "own"
    )
    for line in descriptor.lines {
      context.print(line)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? { nil }
}
