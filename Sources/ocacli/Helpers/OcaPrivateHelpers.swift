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
            flags.formUnion([.cacheValue, .returnCachedValue])
        }
        if contextFlags.contains(.subscribePropertyEvents) {
            flags.formUnion([.subscribeEvents])
        }
        return flags
    }
}

extension OcaBlock {
    var ownerObject: OcaBlock {
        get async throws {
            let owner = try await $owner._getValue(self, flags: [.returnCachedValue])

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

extension OcaRoot {
    func cacheRole(_ role: String) {
        $role.subject.send(.success(role))
    }

    func getRole() async throws -> String {
        try await $role._getValue(self, flags: [.cacheValue, .returnCachedValue])
    }

    private var _cachedRolePath: OcaNamePath? {
        get async {
            var path = [String]()

            var ownerONo: OcaONo = OcaInvalidONo
            var currentObject = self

            repeat {
                guard let role = try? await currentObject.getRole() else {
                    return nil
                }

                if let ownableObject = currentObject as? OcaOwnable,
                   case let .success(owner) = ownableObject.owner
                {
                    ownerONo = owner
                } else {
                    return nil
                }

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

    var rolePath: OcaNamePath {
        get async throws {
            if objectNumber == OcaRootBlockONo {
                return []
            } else if let localRolePath = await _cachedRolePath {
                return localRolePath
            } else if let self = self as? OcaOwnable {
                return try await self.path.0
            } else {
                throw Ocp1Error.objectClassMismatch
            }
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
