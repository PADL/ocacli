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
@_spi(SwiftOCAPrivate) import SwiftOCA

// try to minimize the amount of stuff using private SPI

extension Context {
    var propertyResolutionFlags: _OcaPropertyResolutionFlags {
        var flags = _OcaPropertyResolutionFlags()

        if contextFlags.contains(.cacheProperties) {
            flags.formUnion([.cacheValue, .throwCachedError, .cacheErrors, .returnCachedValue])
        }
        if contextFlags.contains(.subscribePropertyEvents) {
            flags.formUnion([.subscribeEvents])
        }
        return flags
    }

    var cachedPropertyResolutionFlags: _OcaPropertyResolutionFlags {
        propertyResolutionFlags.union([.returnCachedValue])
    }
}

protocol _OcaOwnablePrivate: OcaOwnable {
    func getOwner(flags: _OcaPropertyResolutionFlags) async throws -> OcaONo
}

extension _OcaOwnablePrivate {
    func getOwnerObject(flags: _OcaPropertyResolutionFlags) async throws -> OcaBlock {
        let owner = try await getOwner(flags: flags)
        if owner == OcaInvalidONo {
            throw Ocp1Error.status(.parameterOutOfRange)
        }

        guard let ownerObject = await connectionDelegate?
            .resolve(object: OcaObjectIdentification(
                oNo: owner,
                classIdentification: OcaBlock.classIdentification
            )) as? OcaBlock
        else {
            throw Ocp1Error.status(.badONo)
        }
        return ownerObject
    }
}

extension OcaApplicationNetwork: _OcaOwnablePrivate {
    func getOwner(flags: _OcaPropertyResolutionFlags) async throws -> OcaONo {
        try await $owner._getValue(self, flags: flags)
    }
}

extension OcaAgent: _OcaOwnablePrivate {
    func getOwner(flags: _OcaPropertyResolutionFlags) async throws -> OcaONo {
        try await $owner._getValue(self, flags: flags)
    }
}

extension OcaWorker: _OcaOwnablePrivate {
    func getOwner(flags: _OcaPropertyResolutionFlags) async throws -> OcaONo {
        guard objectNumber != OcaRootBlockONo else { throw Ocp1Error.status(.invalidRequest) }
        return try await $owner._getValue(self, flags: flags)
    }
}

extension OcaRoot {
    func cacheRole(_ role: String) {
        $role.subject.send(.success(role))
    }

    func getRole() async throws -> String {
        try await $role._getValue(self, flags: [.cacheValue, .returnCachedValue])
    }

    func getLocalRolePath(flags: _OcaPropertyResolutionFlags) async throws -> OcaNamePath? {
        if objectNumber == OcaRootBlockONo {
            return []
        }

        var path = [String]()
        var currentObject = self

        repeat {
            guard let role = try? await currentObject.getRole() else {
                return nil
            }

            guard let ownableObject = currentObject as? _OcaOwnablePrivate else {
                return nil
            }

            if ownableObject.objectNumber == OcaRootBlockONo {
                break
            }

            let ownerONo = (try? await ownableObject.getOwner(flags: flags)) ?? OcaInvalidONo
            guard ownerONo != OcaInvalidONo else {
                break // we are at the root
            }

            path.insert(role, at: 0)

            guard let cachedObject = await connectionDelegate?.resolve(cachedObject: ownerONo)
            else {
                return nil
            }
            currentObject = cachedObject
        } while true

        return path
    }

    func getRolePath(flags: _OcaPropertyResolutionFlags) async throws -> OcaNamePath {
        if objectNumber == OcaRootBlockONo {
            return []
        } else if let localRolePath = try await getLocalRolePath(flags: flags) {
            return localRolePath
        } else if let self = self as? OcaOwnable {
            return try await self.path.0
        } else {
            throw Ocp1Error.objectClassMismatch
        }
    }

    func getRolePathString(flags: _OcaPropertyResolutionFlags) async throws -> String {
        if let rolePath = try? await getRolePath(flags: flags) {
            return rolePath.pathString
        } else {
            return objectNumber.oNoString
        }
    }
}

extension Ocp1Connection {
    func resolve<T: OcaRoot>(objectOfUnknownClass: OcaONo) async throws -> T? {
        if let object: T = resolve(cachedObject: objectOfUnknownClass) {
            return object
        }

        let classIdentification =
            try await getClassIdentification(objectNumber: objectOfUnknownClass)
        return resolve(object: OcaObjectIdentification(
            oNo: objectOfUnknownClass,
            classIdentification: classIdentification
        ))
    }
}

func getValueDescription(
    context: Context,
    object: OcaRoot,
    keyPath: PartialKeyPath<OcaRoot>
) async throws -> String? {
    let subject = object[keyPath: keyPath] as! any OcaPropertySubjectRepresentable
    // special hoops to avoid caching, check context for caching environment variable
    guard let value = try? await subject._getValue(
        object,
        flags: context.propertyResolutionFlags
    ) else { return nil }

    if let value = value as? REPLStringConvertible {
        return await value.replString(context: context, object: object)
    } else {
        return String(describing: value)
    }
}

func setValueDescription(
    context: Context,
    object: OcaRoot,
    keyPath: PartialKeyPath<OcaRoot>,
    value: String
) async throws {
    let subject = object[keyPath: keyPath] as! any OcaPropertySubjectRepresentable
    try await subject._set(object, description: value)
}

func getObjectJsonRepresentation(
    context: Context,
    object: OcaRoot,
    options: JSONSerialization.WritingOptions
) async throws -> Data {
    let jsonResultData = try await JSONSerialization.data(
        withJSONObject: object._getJsonValue(flags: context.propertyResolutionFlags),
        options: options
    )
    return jsonResultData
}
