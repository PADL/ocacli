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
            flags.formUnion([.cacheValue, .cacheErrors, .returnCachedValue])
        }
        if contextFlags.contains(.subscribePropertyEvents) {
            flags.formUnion([.subscribeEvents])
        }
        return flags
    }
}

protocol _OcaOwnablePrivate: OcaOwnable {
    func getOwner() async throws -> OcaONo
}

extension _OcaOwnablePrivate {
    var ownerObject: OcaBlock {
        get async throws {
            let owner = try await getOwner()
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
}

extension OcaApplicationNetwork: _OcaOwnablePrivate {
    func getOwner() async throws -> OcaONo {
        try await $owner._getValue(self, flags: [.returnCachedValue])
    }
}

extension OcaAgent: _OcaOwnablePrivate {
    func getOwner() async throws -> OcaONo {
        try await $owner._getValue(self, flags: [.returnCachedValue])
    }
}

extension OcaWorker: _OcaOwnablePrivate {
    func getOwner() async throws -> OcaONo {
        try await $owner._getValue(self, flags: [.returnCachedValue])
    }
}

extension OcaRoot {
    func cacheRole(_ role: String) {
        $role.subject.send(.success(role))
    }

    func getRole() async throws -> String {
        try await $role._getValue(self, flags: [.cacheValue, .returnCachedValue])
    }

    var localRolePath: OcaNamePath? {
        get async {
            var path = [String]()
            var currentObject = self

            repeat {
                if currentObject.objectNumber == OcaRootBlockONo {
                    break
                }

                guard let role = try? await currentObject.getRole() else {
                    return nil
                }

                guard let ownableObject = currentObject as? _OcaOwnablePrivate else {
                    return nil
                }

                let ownerONo = (try? await ownableObject.getOwner()) ?? OcaInvalidONo
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
