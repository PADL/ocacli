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

struct Flags: REPLCommand {
    static let name = ["flags"]

    init() {}

    func execute(with context: Context) async throws {
        for flag in ContextFlagsNames.allCases {
            if context.contextFlags.contains(ContextFlags(flag)) {
                context.print(flag)
            }
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct SetFlag: REPLCommand {
    static let name = ["set-flag", "sf"]

    @REPLCommandArgument
    var flagName: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let flagName, let flag = ContextFlags(string: flagName) else {
            throw Ocp1Error.status(.parameterError)
        }
        context.contextFlags.rawValue |= flag.rawValue
        try await context.connection.set(options: context.contextFlags.connectionOptions)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ClearFlag: REPLCommand {
    static let name = ["clear-flag", "cf"]

    @REPLCommandArgument
    var flagName: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let flagName, let flag = ContextFlags(string: flagName) else {
            throw Ocp1Error.status(.parameterError)
        }
        context.contextFlags.rawValue &= ~(flag.rawValue)
        try await context.connection.set(options: context.contextFlags.connectionOptions)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
