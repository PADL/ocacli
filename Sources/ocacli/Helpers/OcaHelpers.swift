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

protocol OcaBlockMarkerProtocol {}

extension OcaBlock: OcaBlockMarkerProtocol {
    var actionObjectRoles: [String] {
        get async throws {
            try await resolveActionObjects().asyncMap { object in
                (try? await object.getRole()) ?? object.objectNumber.oNoString
            }
        }
    }
}

extension OcaRoot {
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

    var rolePathString: String {
        get async {
            if let rolePath = try? await rolePath {
                return rolePath.pathString
            } else {
                return objectNumber.oNoString
            }
        }
    }
}

extension OcaONo {
    var oNoString: String {
        "<\(self)>"
    }

    init?(oNoString: String) {
        guard oNoString.hasPrefix("<") && oNoString.hasSuffix(">") else {
            return nil
        }
        let offset: Int
        offset = oNoString.hasPrefix("<0x") ? 3 : 1
        let start = oNoString.index(oNoString.startIndex, offsetBy: offset)
        let end = oNoString.index(oNoString.endIndex, offsetBy: -1)
        guard let oNo = OcaONo(String(oNoString[start..<end]), radix: offset == 1 ? 10 : 16) else {
            return nil
        }
        self = oNo
    }
}

func pathComponentsToPathString(_ path: OcaNamePath, absolute: Bool = true) -> String {
    (absolute ? "/" : "") + path.joined(separator: "/")
}

func pathStringToPathComponents(_ path: String) -> (OcaNamePath, Bool) {
    let namePath = OcaNamePath(path.components(separatedBy: "/"))
    if namePath.count > 0, namePath.first!.isEmpty {
        if namePath.allSatisfy(\.isEmpty) {
            return ([], true)
        } else {
            return (Array(namePath[1...]), true)
        }
    } else {
        return (namePath, false)
    }
}

extension Array where Element == String {
    var pathString: String {
        pathComponentsToPathString(self)
    }
}

extension String {
    var pathComponents: ([String], Bool) {
        pathStringToPathComponents(self)
    }
}
