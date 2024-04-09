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

struct ConstructActionObject: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["construct-action-object"]
    static let summary = "Construct action object using a factory"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    @REPLCommandArgument
    var factory: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        _ = try await block.constructActionObject(factory: factory.objectNumber)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteActionObject: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["delete-action-object"]
    static let summary = "Delete block action object"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    @REPLCommandArgument
    var actionObject: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        try await block.delete(actionObject: actionObject.objectNumber)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct AddSignalPath: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["add-signal-path"]
    static let summary = "Add a signal path to a block"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    @REPLCommandArgument
    var source: OcaRoot!

    @REPLCommandArgument
    var sourceID: Int!

    @REPLCommandArgument
    var sink: OcaRoot!

    @REPLCommandArgument
    var sinkID: Int!

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        guard let sourceID = UInt16(exactly: sourceID),
              let sinkID = UInt16(exactly: sinkID)
        else { throw Ocp1Error.status(.parameterOutOfRange) }
        let sourcePort = OcaPort(
            owner: source.objectNumber,
            id: OcaPortID(mode: .output, index: sourceID),
            name: ""
        )
        let sinkPort = OcaPort(
            owner: sink.objectNumber,
            id: OcaPortID(mode: .input, index: sinkID),
            name: ""
        )
        let signalPath = OcaSignalPath(sourcePort: sourcePort, sinkPort: sinkPort)
        let id = try await block.add(signalPath: signalPath)
        context.print(id)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteSignalPath: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["delete-signal-path"]
    static let summary = "Delete a signal path to a block"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        try await block.delete(signalPath: id)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetSignalPathRecursive: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["get-signal-path-recursive"]
    static let summary = "Get recursive signal paths"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        let signalPaths: [OcaUint16: OcaSignalPath] = try await block.getRecursive()
        context.print(signalPaths)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

private extension OcaObjectSearchResultFlags {
    static var replSearchResultFlags: Self {
        [.oNo, .classIdentification, .containerPath, .role]
    }
}

struct FindActionObjects: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["find", "find-action-objects-by-role"]
    static let summary = "Find action objects by search string"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    init() {}

    @REPLCommandArgument
    var searchName: String!

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        let searchResults = try await block.find(
            actionObjectsByRole: searchName,
            nameComparisonType: .containsCaseInsensitive,
            resultFlags: .replSearchResultFlags
        )
        for searchResult in searchResults.filter({ !($0.role?.isEmpty ?? true) })
            .sorted(by: { $1.role! > $0.role! })
        {
            context.print(searchResult.role!)
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct FindActionObjectsRecursive: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["find-recursive", "find-action-objects-by-role-recursive"]
    static let summary = "Recursively find action objects by search string"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    init() {}

    @REPLCommandArgument
    var searchName: String!

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        let searchResults = try await block.findRecursive(
            actionObjectsByRole: searchName,
            nameComparisonType: .containsCaseInsensitive,
            resultFlags: .replSearchResultFlags
        )
        for searchResult in searchResults {
            do {
                guard let object = await context.connection.resolve(object: OcaObjectIdentification(
                    oNo: searchResult.oNo!,
                    classIdentification: searchResult.classIdentification!
                )) else {
                    throw Ocp1Error.status(.processingFailed)
                }
                object.cacheRole(searchResult.role!)

                let rolePath = try await (searchResult.containerPath! + [searchResult.oNo!])
                    .asyncMap {
                        let object = try await context.connection.resolve(objectOfUnknownClass: $0)
                        guard let object else { throw Ocp1Error.status(.processingFailed) }
                        return try await object.getRole()
                    }
                context.print(pathComponentsToPathString(rolePath))
            } catch {
                context.print(searchResult.oNo!.oNoString)
            }
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}