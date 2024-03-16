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

protocol REPLStringConvertible: Sendable {
    func replString(context: Context, object: OcaRoot) async -> String
}

extension Array: REPLStringConvertible where Element: REPLStringConvertible {
    func replString(context: Context, object: OcaRoot) async -> String {
        let replStrings = await asyncMap { await $0.replString(context: context, object: object) }
        return String(describing: replStrings)
    }
}

extension OcaRoot: REPLStringConvertible {
    func replString(context: Context, object: OcaRoot) async -> String {
        if let pathString = try? await rolePath.pathString {
            return pathString
        } else if object.objectNumber == OcaRootBlockONo, let role = try? await getRole() {
            return [role].pathString
        } else {
            return objectNumber.oNoString
        }
    }
}

extension OcaObjectIdentification: REPLStringConvertible {
    func replString(context: Context, object: OcaRoot) async -> String {
        guard let _object = await context.connection.resolve(object: self) else {
            return oNo.oNoString
        }
        return await _object.replString(context: context, object: object)
    }
}

extension OcaBoundedPropertyValue: REPLStringConvertible {
    func replString(context: Context, object: SwiftOCA.OcaRoot) async -> String {
        String(describing: value)
    }
}

struct Show: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["show", "cat"]

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func show(
        context: Context,
        object: OcaRoot,
        property: String,
        keyPath: PartialKeyPath<OcaRoot>
    ) async throws {
        let value = try await getValueStringRepresentation(
            context: context,
            object: object,
            keyPath: keyPath
        )
        context.print("\(property): \(value ?? "null")")
    }

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        for property in object.allPropertyKeyPaths.sorted(by: { $1.key > $0.key }) {
            try await show(
                context: context,
                object: object,
                property: property.key,
                keyPath: property.value
            )
        }
    }
}

struct Get: REPLCommand {
    static let name = ["get"]

    @REPLCommandArgument
    var propertyName: String!

    init() {}

    func execute(with context: Context) async throws {
        var foundProperty = false
        for property in context.currentObject.allPropertyKeyPaths.sorted(by: { $1.key > $0.key }) {
            if property.key == propertyName {
                let value = try await getValueStringRepresentation(
                    context: context,
                    object: context.currentObject,
                    keyPath: property.value
                )
                context.print("\(value ?? "null")")
                foundProperty = true
                break
            }
        }

        if !foundProperty {
            throw Ocp1Error.status(.parameterError)
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
        context.currentObject.allPropertyKeyPaths.map(\.key)
    }
}

struct Dump: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["dump"]

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        let jsonResultData = try await getObjectJsonRepresentation(
            context: context,
            object: object,
            options: .prettyPrinted
        )
        context.print(String(data: jsonResultData, encoding: .utf8)!)
    }
}
