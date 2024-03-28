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
    var propertyResolutionFlags: OcaPropertyResolutionFlags {
        var flags = OcaPropertyResolutionFlags()

        if contextFlags.contains(.cacheProperties) {
            flags.formUnion([.cacheValue, .throwCachedError, .cacheErrors, .returnCachedValue])
        }
        if contextFlags.contains(.subscribePropertyEvents) {
            flags.formUnion([.subscribeEvents])
        }
        return flags
    }

    var cachedPropertyResolutionFlags: OcaPropertyResolutionFlags {
        propertyResolutionFlags.union([.returnCachedValue])
    }
}

extension OcaOwnable {
    func getOwnerObject(flags: OcaPropertyResolutionFlags) async throws -> OcaBlock {
        try await _getOwnerObject(flags: flags)
    }

    func getOwner(flags: OcaPropertyResolutionFlags) async throws -> OcaONo {
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

    func getRolePath(flags: OcaPropertyResolutionFlags) async throws -> OcaNamePath {
        try await _getRolePath(flags: flags)
    }

    private func isOrphan(flags: OcaPropertyResolutionFlags) async throws -> Bool {
        if objectNumber == OcaRootBlockONo {
            return false
        } else
        if let object = self as? OcaOwnable {
            return (try? await object._getOwner(flags: flags)) ?? OcaInvalidONo == OcaInvalidONo
        } else {
            return true
        }
    }

    func getRolePathString(flags: OcaPropertyResolutionFlags) async throws -> String {
        if let rolePathString = try? await getRolePath(flags: flags).pathString {
            return rolePathString
        } else if (try? await isOrphan(flags: flags)) ?? false {
            return try await getRole()
        } else {
            return objectNumber.oNoString
        }
    }
}

extension OcaPropertySubjectRepresentable {
    func getValue<T>(
        _ object: OcaRoot,
        flags: OcaPropertyResolutionFlags,
        transformedBy block: (Value) async throws -> T
    ) async throws -> T {
        let value = try await _getValue(object, flags: flags)
        return try await block(value)
    }

    func setValue<T>(
        _ object: OcaRoot,
        _ newValue: T,
        transformedBy block: (T) async throws -> Any
    ) async throws {
        let value = try await block(newValue)
        try await _setValue(object, value)
    }
}

extension OcaRoot {
    func getValueReplString(
        context: Context,
        keyPath: PartialKeyPath<OcaRoot>
    ) async throws -> String? {
        let subject = self[keyPath: keyPath] as! any OcaPropertySubjectRepresentable

        return try? await subject.getValue(self, flags: context.propertyResolutionFlags) {
            await ocacli.replString(for: $0, context: context, object: self)
        }
    }

    func setValueReplString(
        context: Context,
        keyPath: PartialKeyPath<OcaRoot>,
        _ replString: String
    ) async throws {
        let subject = self[keyPath: keyPath] as! any OcaPropertySubjectRepresentable

        try await subject.setValue(self, replString) {
            try await replValue(
                for: $0,
                type: subject.valueType,
                context: context,
                object: self
            )
        }
    }
}
