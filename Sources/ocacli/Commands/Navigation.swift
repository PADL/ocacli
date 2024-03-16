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

struct Exit: REPLCommand {
    static let name = ["exit", "quit"]

    init() {}

    func execute(with context: Context) async throws {
        exit(0)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ConnectionInfo: REPLCommand {
    static let name = ["connection-info", "conn"]

    init() {}

    func execute(with context: Context) async throws {
        let isConnected = await context.connection.isConnected
        context.print("\(context.connection): \(isConnected ? "connected" : "disconnected")")
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct PrintWorkingPath: REPLCommand {
    static let name = ["pwd"]

    init() {}

    func execute(with context: Context) async throws {
        context.print(context.currentPathString)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct Up: REPLCommand {
    static let name = ["up"]

    init() {}

    func execute(with context: Context) async throws {
        try await context.changeCurrentPath(to: "..")
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ChangePath: REPLCommand, REPLCurrentBlockCompletable {
    static let name = ["cd"]

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        try await context.changeCurrentPath(to: object)
    }
}

struct List: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["list", "ls"]

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        guard let object = (object ?? context.currentObject) as? OcaBlock else {
            return
        }

        try await object.actionObjectRoles.forEach {
            print($0)
        }
    }
}

struct Resolve: REPLCommand {
    static let name = ["resolve"]

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
        await context.print(object.rolePathString)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
