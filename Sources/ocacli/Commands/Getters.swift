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

struct Show: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["show", "cat"]
    static let summary = "Show object properties"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    static func show(
        context: Context,
        object: OcaRoot,
        property: String,
        keyPath: PartialKeyPath<OcaRoot>
    ) async throws -> (String, String?) {
        let value = try await object.getValueReplString(
            context: context,
            keyPath: keyPath
        )
        return (property, value)
    }

    static func show(
        context: Context,
        object: OcaRoot
    ) async throws {
        let results = try await withThrowingTaskGroup(
            of: (String, String?).self,
            returning: [(String, String?)].self
        ) { taskGroup in
            for property in object.allPropertyKeyPaths {
                taskGroup.addTask {
                    try await show(
                        context: context,
                        object: object,
                        property: property.key,
                        keyPath: property.value
                    )
                }
            }
            return try await taskGroup.collect()
        }
        for result in results.sorted(by: { $1.0 > $0.0 }) {
            context.print("\(result.0): \(result.1 ?? "null")")
        }
    }

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        try await Self.show(context: context, object: object)
    }
}

struct Get: REPLCommand {
    static let name = ["get"]
    static let summary = "Retrieve a property"

    @REPLCommandArgument
    var propertyName: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let keyPath = context.currentObject.propertyKeyPath(for: propertyName) else {
            throw Ocp1Error.status(.parameterError)
        }

        let value = try await context.currentObject.getValueReplString(
            context: context,
            keyPath: keyPath
        )
        context.print("\(value ?? "null")")
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
        context.currentObject.allPropertyKeyPaths.map(\.key)
    }
}

struct Dump: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["dump"]
    static let summary = "Recursively display JSON-formatted object"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        let jsonResultData = try await object.getJsonRepresentation(
            context: context,
            options: .prettyPrinted
        )
        context.print(String(data: jsonResultData, encoding: .utf8)!)
    }
}
