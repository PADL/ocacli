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

struct ConnectionInfo: REPLCommand {
    static let name = ["connection-info", "conn"]
    static let summary = "Display connection status"

    init() {}

    func execute(with context: Context) async throws {
        let isConnected = await context.connection.isConnected
        context.print("\(context.connection): \(isConnected ? "connected" : "disconnected")")
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct PrintWorkingPath: REPLCommand {
    static let name = ["pwd"]
    static let summary = "Print current object path"

    init() {}

    func execute(with context: Context) async throws {
        context.print(context.currentPathString)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct Up: REPLCommand {
    static let name = ["up"]
    static let summary = "Change to parent object path"

    init() {}

    func execute(with context: Context) async throws {
        try await context.changeCurrentPath(to: "..")
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ChangePath: REPLCommand, REPLCurrentBlockCompletable {
    static let name = ["cd"]
    static let summary = "Change current object path"

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        try await context.changeCurrentPath(to: object)
    }
}

struct PushPath: REPLCommand, REPLCurrentBlockCompletable {
    static let name = ["pushd"]
    static let summary = "Add current path to top of stack"

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        try await context.pushPath(object)
    }
}

struct PopPath: REPLCommand, REPLCurrentBlockCompletable {
    static let name = ["popd"]
    static let summary = "Remove object from stack"

    init() {}

    func execute(with context: Context) async throws {
        try await context.popPath()
    }
}

struct List: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["list", "ls"]
    static let summary = "Lists action objects in block"
    static var supportedClasses: [OcaClassIdentification] { [OcaBlock.classIdentification] }

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        guard let object = (object ?? context.currentObject) as? OcaBlock else {
            return
        }

        let actionObjects = try await object.resolveActionObjects()

        await withTaskGroup(of: String.self, returning: [String].self) { taskGroup in
            for actionObject in actionObjects {
                taskGroup.addTask {
                    (try? await actionObject.getRole()) ?? actionObject.objectNumber.oNoString
                }
            }
            return await taskGroup.collect()
        }.sorted().forEach { role in
            context.print(role)
        }

        if object == context.currentObject {
            await context.refreshCurrentObjectCompletions()
        }
    }
}

struct ListObjectNumbers: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["list-object-numbers"]
    static let summary = "Lists action objects in block by object number"
    static var supportedClasses: [OcaClassIdentification] { [OcaBlock.classIdentification] }

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        guard let object = (object ?? context.currentObject) as? OcaBlock else {
            return
        }

        for actionObject in try await object
            .getActionObjects(flags: context.contextFlags.cachedPropertyResolutionFlags)
            .sorted(by: { $1.oNo > $0.oNo })
        {
            context.print(actionObject.oNo.oNoString)
        }
    }
}

struct Resolve: REPLCommand {
    static let name = ["resolve"]
    static let summary = "Resolves an object number to a name"

    @REPLCommandArgument
    var oNoString: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let oNoString, let oNo = OcaONo(oNoString: oNoString) else {
            throw Ocp1Error.status(.parameterError)
        }
        guard let object = try await context.connection.resolve(objectOfUnknownClass: oNo) else {
            throw Ocp1Error.status(.badONo)
        }
        try await context
            .print(
                object
                    .getRolePathString(flags: context.contextFlags.cachedPropertyResolutionFlags)
            )
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
