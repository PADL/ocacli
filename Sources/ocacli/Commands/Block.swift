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

struct ConstructActionObject: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["construct-action-object"]
    static let summary = "Construct action object using a factory"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    @REPLCommandArgument
    var factory: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        _ = try await block.constructActionObject(factory: factory.objectNumber)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeleteActionObject: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
    static let name = ["delete-action-object"]
    static let summary = "Delete block action object"

    static var supportedClasses: [OcaClassIdentification] {
        [OcaBlock.classIdentification]
    }

    @REPLCommandArgument
    var actionObject: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let block = context.currentObject as! OcaBlock
        try await block.delete(actionObject: actionObject.objectNumber)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
