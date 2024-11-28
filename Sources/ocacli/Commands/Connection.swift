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
  static let summary = "Connect to device"

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
  static let summary = "Disconnect from device"

  init() {}

  func execute(with context: Context) async throws {
    try await context.connection.disconnect()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ConnectionInfo: REPLCommand {
  static let name = ["connection-info", "conn"]
  static let summary = "Display connection status"

  init() {}

  func execute(with context: Context) async throws {
    let isConnected = await context.connection.isConnected
    context.print("\(context.connection): \(isConnected ? "connected" : "disconnected")")
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct DeviceInfo: REPLCommand {
  static let name = ["device-info"]
  static let summary = "Show device information"

  init() {}

  func execute(with context: Context) async throws {
    let deviceManager = await context.connection.deviceManager
    return try await Show.show(context: context, object: deviceManager)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ClearCache: REPLCommand {
  static let name = ["clear-cache"]
  static let summary = "Clear object cache"

  init() {}

  func execute(with context: Context) async throws {
    await context.connection.clearObjectCache()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

extension Duration {
  var timeInterval: TimeInterval {
    TimeInterval(components.seconds) + Double(components.attoseconds) / 1e18
  }
}

struct Statistics: REPLCommand {
  static let name = ["statistics"]
  static let summary = "Show connection statistics"

  init() {}

  func execute(with context: Context) async throws {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium

    let statistics = await context.connection.statistics

    context.print("connectionState: \(statistics.connectionState)")
    context.print("requestCount: \(statistics.requestCount)")
    context.print("outstandingRequests: \(statistics.outstandingRequests)")
    context.print("cachedObjectCount: \(statistics.cachedObjectCount)")
    context
      .print(
        "subscribedEvents: \(statistics.subscribedEvents.map { "\($0.eventID)@\($0.emitterONo)" })"
      )
    context
      .print(
        "lastMessageSentTime: \(dateFormatter.string(from: statistics.lastMessageSentTime))"
      )
    if let lastMessageReceivedTime = statistics.lastMessageReceivedTime {
      context
        .print(
          "lastMessageReceivedTime: \(dateFormatter.string(from: lastMessageReceivedTime))"
        )
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
