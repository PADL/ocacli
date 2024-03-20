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

enum ContextFlagsNames: Int, CaseIterable {
    case cacheProperties = 0
    case subscribePropertyEvents = 1

    init?(string: String) {
        for flag in Self.allCases {
            if String(describing: flag) == string {
                self = flag
                return
            }
        }

        return nil
    }
}

struct ContextFlags: OptionSet {
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(_ contextFlagsNames: ContextFlagsNames) {
        self.init(rawValue: 1 << contextFlagsNames.rawValue)
    }

    var rawValue: UInt32

    typealias RawValue = UInt32

    static let cacheProperties = ContextFlags(ContextFlagsNames.cacheProperties)
    static let subscribePropertyEvents = ContextFlags(ContextFlagsNames.subscribePropertyEvents)

    init?(string: String) {
        guard let flagName = ContextFlagsNames(string: string) else { return nil }
        self.init(flagName)
    }
}

final class Context {
    let connection: Ocp1Connection
    var contextFlags = ContextFlags()
    var subscriptions = [OcaONo: Ocp1Connection.SubscriptionCancellable]()

    // TODO: UDP support
    // TODO: domain socket support

    init(hostname: String, port: Int, datagram: Bool) async throws {
        guard let port = UInt16(exactly: port) else {
            throw Ocp1Error.serviceResolutionFailed
        }
        let host = Host(name: hostname)
        var connection: Ocp1Connection?
        var savedError: Error?

        // as a synchronous UI that's designed for debugging, we don't cache anything, we always hit
        // the network
        let options = Ocp1ConnectionOptions(refreshDeviceTreeOnConnection: false)

        for hostAddress in host.addresses {
            do {
                var deviceAddressData = Data()
                if hostAddress.contains(":") {
                    var deviceAddress = try sockaddr_in6(hostAddress, port: port)
                    withUnsafeBytes(of: &deviceAddress) { bytes in
                        deviceAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
                    }
                } else {
                    var deviceAddress = try sockaddr_in(hostAddress, port: port)
                    withUnsafeBytes(of: &deviceAddress) { bytes in
                        deviceAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
                    }
                }
                if datagram {
                    connection = try await Ocp1UDPConnection(
                        deviceAddress: deviceAddressData,
                        options: options
                    )
                } else {
                    connection = try await Ocp1TCPConnection(
                        deviceAddress: deviceAddressData,
                        options: options
                    )
                }
                if let connection {
                    try await connection.connect()
                    break
                }
            } catch {
                savedError = error
            }
        }

        guard let connection else {
            guard let savedError else {
                throw Ocp1Error.serviceResolutionFailed
            }
            throw savedError
        }

        self.connection = connection
        currentObject = await connection.rootBlock
        try await changeCurrentPath(to: connection.rootBlock)
    }

    func finish() async {
        try? await connection.disconnect()
    }

    private(set) var currentObject: OcaRoot
    private(set) var currentObjectPath: OcaNamePath? = [""]
    private(set) var currentObjectCompletions: [String]? = [] // bool if container

    func findObject(
        with pathComponents: OcaNamePath,
        relativeTo baseObject: OcaBlock
    ) async throws -> (OcaObjectIdentification, OcaString) {
        let flags =
            OcaObjectSearchResultFlags([.oNo, .classIdentification, .containerPath, .role])
        let searchResult = try await baseObject.find(
            actionObjectsByPath: pathComponents,
            resultFlags: flags
        )

        guard searchResult.count == 1, let oNo = searchResult[0].oNo,
              let role = searchResult[0].role,
              let classIdentification = searchResult[0].classIdentification
        else {
            throw Ocp1Error.objectNotPresent
        }

        return (OcaObjectIdentification(
            oNo: oNo,
            classIdentification: classIdentification
        ), role)
    }

    func resolvePath<T: OcaRoot>(_ path: String) async throws -> T {
        let object: OcaRoot?

        if let oNo = OcaONo(oNoString: path) {
            object = try await connection.resolve(objectOfUnknownClass: oNo)
        } else if path == "." {
            object = currentObject
        } else if path == "..", let currentObject = currentObject as? OcaOwnable {
            guard let owner = try currentObject.owner.asOptionalResult().get() else {
                throw Ocp1Error.objectNotPresent
            }
            object = await connection
                .resolve(object: OcaObjectIdentification(
                    oNo: owner,
                    classIdentification: OcaBlock.classIdentification
                ))
        } else {
            let pathComponents = path.pathComponents

            guard let baseObject = (
                pathComponents.1 ? await connection
                    .rootBlock : currentObject
            ) as? OcaBlock else {
                throw Ocp1Error.objectClassMismatch
            }

            if pathComponents.0.isEmpty {
                object = baseObject
            } else {
                let (objectIdentification, role) = try await findObject(
                    with: pathComponents.0,
                    relativeTo: baseObject
                )

                object = await connection.resolve(object: objectIdentification)
                object?.cacheRole(role)
            }
        }
        guard let object else {
            throw Ocp1Error.objectNotPresent
        }
        guard let object = object as? T else {
            throw Ocp1Error.objectClassMismatch
        }
        return object
    }

    func changeCurrentPath(to path: String) async throws {
        if path.isEmpty { return }
        let object: OcaBlock = try await resolvePath(path)
        try await changeCurrentPath(to: object)
    }

    func changeCurrentPath(to object: OcaRoot) async throws {
        let newRolePath = try await object.rolePath
        currentObject = object
        currentObjectPath = newRolePath
        if let object = object as? OcaBlock {
            currentObjectCompletions = try? await object.actionObjectRoles.map { role in
                role.contains(" ") ? "\"\(role)\"" : role
            }
        } else {
            currentObjectCompletions = nil
        }
    }

    var currentPathString: String {
        if let currentObjectPath {
            return currentObjectPath.pathString
        } else {
            return currentObject.objectNumber.oNoString
        }
    }

    let lock = NSRecursiveLock()

    func print(_ items: Any...) {
        lock.lock()
        defer { lock.unlock() }
        Swift.print(items, separator: " ", terminator: "\n")
    }

    func onPropertyEvent(event: OcaEvent, eventData data: Data) {
        let decoder = Ocp1Decoder()
        guard let propertyID = try? decoder.decode(
            OcaPropertyID.self,
            from: data
        ) else { return }

        Task {
            let emitter = await connection.resolve(cachedObject: event.emitterONo)
            let emitterPath = emitter != nil ? try await emitter!.rolePath.pathString : event
                .emitterONo.oNoString
            self
                .print(
                    "event \(event.eventID) from \(emitterPath) property \(propertyID) data \(data)"
                )
        }
    }
}
