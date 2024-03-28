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

struct Set: REPLCommand {
    static let name = ["set"]
    static let summary = "Set a property"

    @REPLCommandArgument
    var propertyName: String!

    @REPLCommandArgument
    var propertyValue: String!

    init() {}

    func execute(with context: Context) async throws {
        var foundProperty: (String, PartialKeyPath<OcaRoot>)?
        for property in context.currentObject.allPropertyKeyPaths {
            if property.key == propertyName {
                foundProperty = (property.key, property.value)
                break
            }
        }

        guard let foundProperty else {
            throw Ocp1Error.status(.parameterError)
        }

        try await context.currentObject.setValueReplString(
            context: context,
            keyPath: foundProperty.1,
            propertyValue
        )
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
        context.currentObject.allPropertyKeyPaths.map(\.key)
    }
}
