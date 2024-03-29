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

struct LockNoReadWrite: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["lock-total", "lock-no-read-write"]
    static let summary = "Lock object from reads and writes"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        try await object.setLockNoReadWrite()
    }
}

struct Unlock: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["unlock"]
    static let summary = "Unlock object"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        try await object.unlock()
    }
}

struct LockNoWrite: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["lock", "lock-readonly", "lock-no-write"]
    static let summary = "Lock object from writes"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        try await object.setLockNoWrite()
    }
}
