//
// Copyright (c) 2026 PADL Software Pty Ltd
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

// AES70-2024 counter set and counter notifier commands.

/// A counter set ID, decoded where it has one of the standard layouts.
func counterSetIDDescription(_ id: OcaCounterSetID) -> String {
  if let decoded = try? OcaMediaStreamEndpointCounterSetID(blob: id), (try? decoded.blob) == id {
    return "owner=\(decoded.ownerONo.oNoString),endpoint=\(decoded.endpointID)"
  }
  if let decoded = try? OcaPropertyCounterSetID(blob: id), (try? decoded.blob) == id {
    return "owner=\(decoded.ownerONo.oNoString),property=\(decoded.propertyID)"
  }
  return id.isEmpty ? "none" : "0x\(Data(id).hexString)"
}

extension OcaCounterSet {
  var replLines: [String] {
    ["counter set \(counterSetIDDescription(id))"] + counter.map { counter in
      let notifiers = counter.notifiers.isEmpty ? "none" : counter.notifiers.map(\.oNoString)
        .joined(separator: ",")
      return "\(counter.id)\t\(counter.role)\tvalue=\(counter.value)\tinitial=\(counter.initialValue)\tnotifiers=\(notifiers)"
    }
  }
}

extension OcaCounterUpdate {
  var replLine: String {
    "\(counterSetIDDescription(counterSetID))\t\(counterID)\t\(value)"
  }
}

/// A counter ID argument, checked against OcaID16's range.
func parseCounterID(_ id: Int) throws -> OcaID16 {
  guard let id = OcaID16(exactly: id) else { throw Ocp1Error.status(.parameterOutOfRange) }
  return id
}

private struct CounterSetError: Error, CustomStringConvertible, LocalizedError {
  let description: String
  var errorDescription: String? { description }
}

/// The classes holding a counter set of their own, whose methods differ only in name.
private protocol CounterSetOwner: OcaRoot {
  func getCounterSet() async throws -> OcaCounterSet
  func attachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws
  func detachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws
  func resetCounters(counterID: OcaID16?) async throws
}

private let counterSetOwnerClasses = [
  OcaNetworkInterface.classIdentification,
  OcaNetworkApplication.classIdentification,
  OcaCounterSetAgent.classIdentification,
]

extension OcaNetworkInterface: CounterSetOwner {
  fileprivate func resetCounters(counterID: OcaID16?) async throws {
    guard counterID == nil else {
      throw CounterSetError(description: "OcaNetworkInterface resets only its whole counter set")
    }
    try await resetCounters()
  }
}

extension OcaNetworkApplication: CounterSetOwner {
  fileprivate func resetCounters(counterID: OcaID16?) async throws {
    guard counterID == nil else {
      throw CounterSetError(description: "OcaNetworkApplication resets only its whole counter set")
    }
    try await resetCounters()
  }
}

extension OcaCounterSetAgent: CounterSetOwner {
  fileprivate func attachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws {
    try await attachCounterNotifier(id: counterID, oNo: oNo)
  }

  fileprivate func detachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws {
    try await detachCounterNotifier(id: counterID, oNo: oNo)
  }

  fileprivate func resetCounters(counterID: OcaID16?) async throws {
    if let counterID {
      try await resetCounter(id: counterID)
    } else {
      try await resetCounterSet()
    }
  }
}

private extension Context {
  var counterSetOwner: any CounterSetOwner {
    get throws {
      guard let owner = currentObject as? any CounterSetOwner else { throw Ocp1Error.objectClassMismatch }
      return owner
    }
  }
}

/// The counter IDs of the current object's set, for completing a counter argument.
private func counterIDCompletions(with context: Context) async -> [String]? {
  guard let owner = context.currentObject as? any CounterSetOwner,
        let counterSet = try? await owner.getCounterSet()
  else { return nil }
  return counterSet.counter.map { String($0.id) }
}

struct GetCounters: REPLCommand, REPLClassSpecificCommand {
  static let name = ["get-counters", "counters"]
  static let summary = "Show the object's counter set"

  static var supportedClasses: [OcaClassIdentification] { counterSetOwnerClasses }

  init() {}

  func execute(with context: Context) async throws {
    for line in try await context.counterSetOwner.getCounterSet().replLines {
      context.print(line)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}

struct AttachCounterNotifier: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["attach-counter-notifier"]
  static let summary = "Attach a counter notifier to a counter: <counter ID> <notifier>"

  static var supportedClasses: [OcaClassIdentification] { counterSetOwnerClasses }

  @REPLCommandArgument
  var counterID: Int!

  @REPLCommandArgument
  var notifier: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    try await context.counterSetOwner.attachCounterNotifier(
      counterID: parseCounterID(counterID),
      oNo: notifier
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    switch replArgumentIndex(currentBuffer) {
    case 0: await counterIDCompletions(with: context)
    case 1: await context.resolveCompletions(forPartialRolePath: currentBuffer.replFinalWord)
    default: nil
    }
  }
}

struct DetachCounterNotifier: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["detach-counter-notifier"]
  static let summary = "Detach a counter notifier from a counter: <counter ID> <notifier>"

  static var supportedClasses: [OcaClassIdentification] { counterSetOwnerClasses }

  @REPLCommandArgument
  var counterID: Int!

  @REPLCommandArgument
  var notifier: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    try await context.counterSetOwner.detachCounterNotifier(
      counterID: parseCounterID(counterID),
      oNo: notifier
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    switch replArgumentIndex(currentBuffer) {
    case 0: await counterIDCompletions(with: context)
    case 1: await context.resolveCompletions(forPartialRolePath: currentBuffer.replFinalWord)
    default: nil
    }
  }
}

struct ResetCounters: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["reset-counters"]
  static let summary = "Reset one counter, or the whole counter set: [counter ID]"

  static var supportedClasses: [OcaClassIdentification] { counterSetOwnerClasses }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var counterID: Int?

  init() {}

  func execute(with context: Context) async throws {
    try await context.counterSetOwner.resetCounters(counterID: counterID.map(parseCounterID))
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await counterIDCompletions(with: context)
  }
}

// MARK: - OcaCounterNotifier

private let relationalOperatorNames: [(String, OcaRelationalOperator)] = [
  ("none", .none),
  ("eq", .equality),
  ("ne", .inequality),
  ("gt", .greaterThan),
  ("ge", .greaterThanOrEqual),
  ("lt", .lessThan),
  ("le", .lessThanOrEqual),
]

private extension OcaRelationalOperator {
  var replName: String {
    relationalOperatorNames.first { $0.1 == self }!.0
  }

  init(replName: String) throws {
    guard let value = relationalOperatorNames.first(where: { $0.0 == replName })?.1 else {
      throw Ocp1Error.status(.badFormat)
    }
    self = value
  }
}

private extension OcaCounterNotifierFilterParameters {
  var replLine: String {
    "threshold=\(threshold)\top=\(`operator`.replName)\tperiod=\(period)\tdelta=\(countDelta)"
  }
}

private extension OcaCounterNotifier {
  /// The filter parameters, or nil when none are set: an OCP.1 getter then answers
  /// ParameterOutOfRange.
  func filterParametersIfSet() async throws -> OcaCounterNotifierFilterParameters? {
    do {
      return try await $filterParameters._getValue(self, flags: [])
    } catch Ocp1Error.status(.parameterOutOfRange) {
      return nil
    }
  }
}

struct GetCounterFilter: REPLCommand, REPLClassSpecificCommand {
  static let name = ["get-counter-filter"]
  static let summary = "Show a counter notifier's filter parameters"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaCounterNotifier.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let notifier = context.currentObject as! OcaCounterNotifier
    let parameters = try await notifier.filterParametersIfSet()
    context.print(parameters?.replLine ?? "no filter set")
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}

struct SetCounterFilter: REPLCommand, REPLOptionalArguments, REPLClassSpecificCommand {
  static let name = ["set-counter-filter"]
  static let summary =
    "Change a counter notifier's filter parameters: [threshold=N] [op=none|eq|ne|gt|ge|lt|le] [period=seconds] [delta=N]"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaCounterNotifier.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var argument1: String?

  @REPLCommandArgument
  var argument2: String?

  @REPLCommandArgument
  var argument3: String?

  @REPLCommandArgument
  var argument4: String?

  init() {}

  func execute(with context: Context) async throws {
    let notifier = context.currentObject as! OcaCounterNotifier
    // unset parameters count as all zero, as the notifier takes them
    let current = try await notifier.filterParametersIfSet()
    var threshold = current?.threshold ?? 0
    var `operator` = current?.operator ?? .none
    var period = current?.period ?? 0
    var countDelta = current?.countDelta ?? 0

    for argument in [argument1, argument2, argument3, argument4].compactMap(\.self) {
      let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
      guard pair.count == 2 else { throw Ocp1Error.status(.badFormat) }
      switch pair[0] {
      case "threshold":
        guard let value = OcaUint64(pair[1]) else { throw Ocp1Error.status(.badFormat) }
        threshold = value
      case "op":
        `operator` = try OcaRelationalOperator(replName: pair[1])
      case "period":
        guard let value = OcaTimeInterval(pair[1]) else { throw Ocp1Error.status(.badFormat) }
        period = value
      case "delta":
        guard let value = OcaUint64(pair[1]) else { throw Ocp1Error.status(.badFormat) }
        countDelta = value
      default:
        throw Ocp1Error.status(.badFormat)
      }
    }

    try await notifier.$filterParameters._setValue(notifier, OcaCounterNotifierFilterParameters(
      threshold: threshold,
      operator: `operator`,
      period: period,
      countDelta: countDelta
    ))
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    ["threshold=", "period=", "delta="] + relationalOperatorNames.map { "op=\($0.0)" }
  }
}

struct GetLastUpdate: REPLCommand, REPLClassSpecificCommand {
  static let name = ["get-last-update"]
  static let summary = "Show a counter notifier's last update: <set ID> <counter ID> <value>"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaCounterNotifier.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let notifier = context.currentObject as! OcaCounterNotifier
    for update in try await notifier.getLastUpdate() {
      context.print(update.replLine)
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}

struct WatchCounters: REPLCommand, REPLOptionalArguments, REPLClassSpecificCommand {
  static let name = ["watch-counters"]
  static let summary =
    "Print a counter notifier's updates until escape is pressed, or for some time: [seconds]"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaCounterNotifier.classIdentification]
  }

  /// Without a terminal there is no escape key, so an untimed watch ends after this long.
  private static let defaultNonInteractiveDuration = 10.0

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var seconds: Double?

  init() {}

  func execute(with context: Context) async throws {
    let notifier = context.currentObject as! OcaCounterNotifier
    let event = OcaEvent(emitterONo: notifier.objectNumber, eventID: OcaCounterNotifier.counterUpdateEventID)
    let cancellable = try await context.connection.addSubscription(
      label: "com.padl.ocacli.watch-counters",
      event: event
    ) { _, data in
      let eventData = try Ocp1Decoder().decode(OcaCounterUpdateEventData.self, from: data)
      for update in eventData.updates {
        context.print(update.replLine)
      }
    }

    let duration = seconds ?? (context.lineReader == nil ? Self.defaultNonInteractiveDuration : nil)
    do {
      try await context.withInterruption {
        if let duration {
          try await Task.sleep(for: .seconds(duration))
        } else {
          while true { try await Task.sleep(for: .seconds(3600)) }
        }
      }
    } catch is CancellationError {
    } catch {
      try? await context.connection.removeSubscription(cancellable)
      throw error
    }
    try await context.connection.removeSubscription(cancellable)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}
