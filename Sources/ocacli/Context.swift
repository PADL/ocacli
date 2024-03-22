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
    /// cache property lookups
    case cacheProperties = 0
    /// subscribe to property events, so properties are updated asynchronously
    case subscribePropertyEvents = 1
    /// connected device supports findActionObjectsByPath() method
    case supportsFindActionObjectsByPath = 2
    case enableRolePathLookupCache = 3
    case refreshDeviceTreeOnConnection = 4
    case automaticReconnect = 5

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
    static let supportsFindActionObjectsByPath = ContextFlags(
        ContextFlagsNames
            .supportsFindActionObjectsByPath
    )
    static let enableRolePathLookupCache = ContextFlags(ContextFlagsNames.enableRolePathLookupCache)
    static let refreshDeviceTreeOnConnection = ContextFlags(
        ContextFlagsNames
            .refreshDeviceTreeOnConnection
    )
    static let automaticReconnect = ContextFlags(ContextFlagsNames.automaticReconnect)

    init?(string: String) {
        guard let flagName = ContextFlagsNames(string: string) else { return nil }
        self.init(flagName)
    }

    var connectionOptions: Ocp1ConnectionOptions {
        Ocp1ConnectionOptions(
            automaticReconnect: contains(.automaticReconnect),
            refreshDeviceTreeOnConnection: contains(.refreshDeviceTreeOnConnection)
        )
    }
}

final class Context {
    let connection: Ocp1Connection
    var contextFlags: ContextFlags = [.enableRolePathLookupCache, .supportsFindActionObjectsByPath]
    var subscriptions = [OcaONo: Ocp1Connection.SubscriptionCancellable]()

    // TODO: UDP support
    // TODO: domain socket support

    private(set) var currentObject: OcaRoot
    private(set) var currentObjectPath: OcaNamePath? = [""]
    private(set) var currentObjectCompletions: [String]? = [] // bool if container
    private var sparseRolePathCache: [OcaNamePath: OcaRoot] =
        [:] // cache FindObjectsByRole() results

    init(hostname: String, port: Int, datagram: Bool) async throws {
        guard let port = UInt16(exactly: port) else {
            throw Ocp1Error.serviceResolutionFailed
        }
        let host = Host(name: hostname)
        var connection: Ocp1Connection?
        var savedError: Error?

        // as a synchronous UI that's designed for debugging, we don't cache anything except for
        // role names and the hierarchy which we presume not to change
        let options = contextFlags.connectionOptions
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

    func findObjectCached(
        rolePath path: OcaNamePath,
        relativeTo baseObject: OcaBlock
    ) async throws -> OcaRoot {
        precondition(contextFlags.contains(.enableRolePathLookupCache))

        var object: OcaRoot! = baseObject
        for pathComponent in path {
            guard let block = object as? OcaBlock else {
                throw Ocp1Error.objectClassMismatch
            }

            var childObject: OcaRoot?

            for role in try await block.cachedActionObjectRoles {
                if role.1 == pathComponent {
                    childObject = role.0
                    break
                }
            }

            guard let childObject else {
                throw Ocp1Error.objectNotPresent
            }

            object = childObject
        }

        guard let object else { throw Ocp1Error.objectNotPresent }
        return object
    }

    private static func findObjectFallback(
        with rolePath: OcaNamePath,
        relativeTo baseObject: OcaBlock
    ) async throws -> OcaRoot {
        var object: OcaRoot! = baseObject
        for pathComponent in rolePath {
            guard let block = object as? OcaBlock else {
                throw Ocp1Error.objectClassMismatch
            }

            var childObject: OcaRoot?

            for actionObject in try await block.resolveActionObjects() {
                let role = try await actionObject.getRole()
                if role == pathComponent {
                    childObject = actionObject
                    break
                }
            }

            guard let childObject else {
                throw Ocp1Error.objectNotPresent
            }

            object = childObject
        }

        guard let object else { throw Ocp1Error.objectNotPresent }
        return object
    }

    private static func findObject(
        with rolePath: OcaNamePath,
        relativeTo baseObject: OcaBlock
    ) async throws -> (OcaObjectIdentification, OcaString) {
        let flags =
            OcaObjectSearchResultFlags([.oNo, .classIdentification, .containerPath, .role])
        let searchResult = try await baseObject.find(
            actionObjectsByPath: rolePath,
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

    private func resolve(
        rolePath path: OcaNamePath,
        relativeTo baseObject: OcaBlock
    ) async throws -> OcaRoot? {
        var object: OcaRoot?

        if contextFlags.contains(.enableRolePathLookupCache) {
            if contextFlags.contains(.supportsFindActionObjectsByPath) {
                object = sparseRolePathCache[path]
            }

            if object == nil {
                do {
                    object = try await findObjectCached(rolePath: path, relativeTo: baseObject)
                } catch Ocp1Error.objectNotPresent, Ocp1Error.noInitialValue {}
            }
        }

        if object == nil, contextFlags.contains(.supportsFindActionObjectsByPath) {
            do {
                let objectIdentificationAndRole = try await Context.findObject(
                    with: path,
                    relativeTo: baseObject
                )
                object = await connection.resolve(object: objectIdentificationAndRole.0)

                /// sparseRolePathCache is used to cache results of FindActionObjectsByPath()
                /// where we haven't necessarily traversed the complete object hierarchy
                if let object {
                    object.cacheRole(objectIdentificationAndRole.1)
                    sparseRolePathCache[path] = object
                }
            } catch Ocp1Error.status(.notImplemented) {
                contextFlags.remove(.supportsFindActionObjectsByPath)
            }
        }

        if object == nil {
            object = try await Context.findObjectFallback(
                with: path,
                relativeTo: baseObject
            )
        }

        return object
    }

    func resolve<T: OcaRoot>(rolePath path: String) async throws -> T {
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
                object = try await resolve(rolePath: pathComponents.0, relativeTo: baseObject)
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

    func changeCurrentPath(to rolePath: String) async throws {
        if rolePath.isEmpty { return }
        let object: OcaBlock = try await resolve(rolePath: rolePath)
        try await changeCurrentPath(to: object)
    }

    func changeCurrentPath(to object: OcaRoot) async throws {
        let newRolePath = try await object.rolePath
        currentObject = object
        currentObjectPath = newRolePath
        if let object = object as? OcaBlock {
            currentObjectCompletions = try? await object.cachedActionObjectRoles.map { _, role in
                role.contains(" ") ? "\"\(role)\"" : role
            }
            currentObjectCompletions?.append(contentsOf: sparseRolePathCache.keys.filter {
                Array($0.prefix(newRolePath.count)) == newRolePath
            }.map { pathComponentsToPathString($0) })
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
