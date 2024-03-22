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

struct Connect: REPLCommand {
    static let name = ["connect"]

    init() {}

    func execute(with context: Context) async throws {
        if await context.connection.isConnected == false {
            try await context.connection.connect()
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct Disconnect: REPLCommand {
    static let name = ["disconnect"]

    init() {}

    func execute(with context: Context) async throws {
        if await context.connection.isConnected {
            try await context.connection.disconnect()
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeviceInfo: REPLCommand {
    static let name = ["device-info"]

    init() {}

    func execute(with context: Context) async throws {
        let deviceManager = await context.connection.deviceManager
        return try await Show.show(context: context, object: deviceManager)
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
