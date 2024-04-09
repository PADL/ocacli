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
        [OcaWorker.classIdentification, OcaMediaTransportNetwork.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let port: String
        if let worker = context.currentObject as? OcaWorker {
            port = try await worker.get(portID: OcaPortID(mode: .input, index: id))
        } else if let mediaTransportNetwork = context.currentObject as? OcaMediaTransportNetwork {
            port = try await mediaTransportNetwork.get(portID: OcaPortID(mode: .input, index: id))
        } else {
            throw Ocp1Error.objectClassMismatch
        }
        context.print(port)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetOutputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["get-output-port-name"]
    static let summary = "Get output port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification, OcaMediaTransportNetwork.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let port: String
        if let worker = context.currentObject as? OcaWorker {
            port = try await worker.get(portID: OcaPortID(mode: .output, index: id))
        } else if let mediaTransportNetwork = context.currentObject as? OcaMediaTransportNetwork {
            port = try await mediaTransportNetwork.get(portID: OcaPortID(mode: .output, index: id))
        } else {
            throw Ocp1Error.objectClassMismatch
        }
        context.print(port)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetInputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["set-input-port-name"]
    static let summary = "Set input port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification, OcaMediaTransportNetwork.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    @REPLCommandArgument
    var name: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        if let worker = context.currentObject as? OcaWorker {
            try await worker.set(portID: OcaPortID(mode: .input, index: id), name: name)
        } else if let mediaTransportNetwork = context.currentObject as? OcaMediaTransportNetwork {
            try await mediaTransportNetwork.set(
                portID: OcaPortID(mode: .input, index: id),
                name: name
            )
        } else {
            throw Ocp1Error.objectClassMismatch
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetOutputPortName: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["set-output-port-name"]
    static let summary = "Set output port name"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification, OcaMediaTransportNetwork.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    @REPLCommandArgument
    var name: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        if let worker = context.currentObject as? OcaWorker {
            try await worker.set(portID: OcaPortID(mode: .output, index: id), name: name)
        } else if let mediaTransportNetwork = context.currentObject as? OcaMediaTransportNetwork {
            try await mediaTransportNetwork.set(
                portID: OcaPortID(mode: .output, index: id),
                name: name
            )
        } else {
            throw Ocp1Error.objectClassMismatch
        }
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

struct GetInputPortClockMapEntry: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["get-input-clock-map-entry"]
    static let summary = "Get input port clock map entry"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let port: OcaPortClockMapEntry = try await worker
            .get(portID: OcaPortID(mode: .input, index: id))
        context.print(port)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct GetOutputPortClockMapEntry: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["get-output-clock-map-entry"]
    static let summary = "Get output port clock map entry"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let port: OcaPortClockMapEntry = try await worker
            .get(portID: OcaPortID(mode: .output, index: id))
        context.print(port)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetInputPortClockMapEntry: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand, REPLOptionalArguments
{
    var minimumRequiredArguments: Int { 2 }

    static let name = ["set-input-clock-map-entry"]
    static let summary = "Set input port clock map entry"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    @REPLCommandArgument
    var clock: OcaRoot!

    @REPLCommandArgument
    var srcTypeString: String!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let srcType: OcaSamplingRateConverterType
        if let srcTypeString {
            guard let _srcType = OcaSamplingRateConverterType
                .value(for: srcTypeString) as! OcaSamplingRateConverterType?
            else {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            srcType = _srcType
        } else {
            srcType = .none
        }
        try await worker.set(
            portID: OcaPortID(mode: .input, index: id),
            portClockMapEntry: OcaPortClockMapEntry(clockONo: clock.objectNumber, srcType: srcType)
        )
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetOutputPortClockMapEntry: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand, REPLOptionalArguments
{
    var minimumRequiredArguments: Int { 2 }

    static let name = ["set-output-clock-map-entry"]
    static let summary = "Set output port clock map entry"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaWorker.classIdentification]
    }

    @REPLCommandArgument
    var id: Int!

    @REPLCommandArgument
    var clock: OcaRoot!

    @REPLCommandArgument
    var srcTypeString: String!

    init() {}

    func execute(with context: Context) async throws {
        let worker = context.currentObject as! OcaWorker
        guard let id = UInt16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
        let srcType: OcaSamplingRateConverterType
        if let srcTypeString {
            guard let _srcType = OcaSamplingRateConverterType
                .value(for: srcTypeString) as! OcaSamplingRateConverterType?
            else {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            srcType = _srcType
        } else {
            srcType = .none
        }
        try await worker.set(
            portID: OcaPortID(mode: .output, index: id),
            portClockMapEntry: OcaPortClockMapEntry(clockONo: clock.objectNumber, srcType: srcType)
        )
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteInputPortClockMapEntry: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["delete-input-clock-map-entry"]
    static let summary = "Delete input port clock map entry"

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

struct DeleteOutputPortClockMapEntry: REPLCommand, REPLCurrentBlockCompletable,
    REPLClassSpecificCommand
{
    static let name = ["delete-output-clock-map-entry"]
    static let summary = "Delete output port clock map entry"

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
