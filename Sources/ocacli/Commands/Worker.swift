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

struct GetInputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["get-input-port-name"]
    static let summary = "Get input port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let port: OcaString = try await worker.get(portID: OcaPortID(mode: .input, index: id))
        context.print(port)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetOutputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["get-output-port-name"]
    static let summary = "Get output port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let port: OcaString = try await worker.get(portID: OcaPortID(mode: .output, index: id))
        context.print(port)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetInputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["set-input-port-name"]
    static let summary = "Set input port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    @REPLCommandArgument
    var name: String!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        try await worker.set(portID: OcaPortID(mode: .input, index: id), name: name)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetOutputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["set-output-port-name"]
    static let summary = "Set output port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    @REPLCommandArgument
    var name: String!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        try await worker.set(portID: OcaPortID(mode: .output, index: id), name: name)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteInputPort: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["delete-input-port"]
    static let summary = "Delete input port"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        try await worker.delete(portID: OcaPortID(mode: .input, index: id))
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteOutputPort: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["delete-output-port"]
    static let summary = "Delete output port"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        try await worker.delete(portID: OcaPortID(mode: .output, index: id))
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
