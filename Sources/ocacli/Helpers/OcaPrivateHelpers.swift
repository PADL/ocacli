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

extension OcaOwnable {
    func getOwnerObject(flags: _OcaPropertyResolutionFlags) async throws -> OcaBlock {
        try await _getOwnerObject(flags: flags)
    }

    func getOwner(flags: _OcaPropertyResolutionFlags) async throws -> OcaONo {
        try await _getOwner(flags: flags)
    }
}

extension OcaRoot {
    func cacheRole(_ role: String) {
        _set(role: role)
    }

    func getRole() async throws -> String {
        try await _getRole()
    }

    func getRolePath(flags: _OcaPropertyResolutionFlags) async throws -> OcaNamePath {
        try await _getRolePath(flags: flags)
    }

    private func isOrphan(flags: _OcaPropertyResolutionFlags) async throws -> Bool {
        if objectNumber == OcaRootBlockONo {
            return false
        } else
        if let object = self as? OcaOwnable {
            return (try? await object._getOwner(flags: flags)) ?? OcaInvalidONo == OcaInvalidONo
        } else {
            return true
        }
    }

    func getRolePathString(flags: _OcaPropertyResolutionFlags) async throws -> String {
        if let rolePathString = try? await getRolePath(flags: flags).pathString {
            return rolePathString
        } else if (try? await isOrphan(flags: flags)) ?? false {
            return try await getRole()
        } else {
            return objectNumber.oNoString
        }
    }
}

extension OcaRoot {
    func getValueDescription(
        context: Context,
        keyPath: PartialKeyPath<OcaRoot>
    ) async throws -> String? {
        let subject = self[keyPath: keyPath] as! any OcaPropertySubjectRepresentable
        // special hoops to avoid caching, check context for caching environment variable
        guard let value = try? await subject._getValue(
            self,
            flags: context.propertyResolutionFlags
        ) else { return nil }

        if let value = value as? REPLStringConvertible {
            return await value.replString(context: context, object: self)
        } else {
            return String(describing: value)
        }
    }

    func setValueDescription(
        context: Context,
        keyPath: PartialKeyPath<OcaRoot>,
        value: String
    ) async throws {
        let subject = self[keyPath: keyPath] as! any OcaPropertySubjectRepresentable
        try await subject._set(self, description: value)
    }

    func getJsonRepresentation(
        context: Context,
        options: JSONSerialization.WritingOptions
    ) async throws -> Data {
        let jsonResultData = try await JSONSerialization.data(
            withJSONObject: _getJsonValue(flags: context.propertyResolutionFlags),
            options: options
        )
        return jsonResultData
    }
}
