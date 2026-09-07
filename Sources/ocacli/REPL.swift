//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
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

import AsyncLineReader
import Foundation
import SwiftOCA

private protocol REPLCommandArgumentMarker {}

protocol REPLOptionalArguments {
  var minimumRequiredArguments: Int { get }
}

protocol REPLClassSpecificCommand {
  static var supportedClasses: [OcaClassIdentification] { get }
}

@propertyWrapper
class REPLCommandArgument<T>: REPLCommandArgumentMarker {
  var wrappedValue: T?

  init(wrappedValue: T?) {
    self.wrappedValue = wrappedValue
  }
}

protocol REPLCommand {
  static var name: [String] { get }
  static var summary: String { get }

  init()
  func execute(with context: Context) async throws
  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]?
}

extension REPLCommand {
  static var isUsableWhenDisconnected: Bool {
    self == Help.self || self == Statistics.self || self == Connect.self || self == Disconnect
      .self || self == Exit.self
  }

  var isUsableWhenDisconnected: Bool {
    Self.isUsableWhenDisconnected
  }
}

protocol REPLCurrentBlockCompletable: REPLCommand {}

extension REPLCurrentBlockCompletable {
  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    await context.resolveCompletions(forPartialRolePath: currentBuffer.replFinalWord)
  }
}

struct Exit: REPLCommand {
  static let name = ["exit", "quit"]
  static let summary = "Exit the OCA CLI"

  init() {}

  func execute(with context: Context) async throws {
    await context.finish()
    exit(0)
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}

struct Help: REPLCommand {
  static let name = ["help", "?"]
  static let summary = "Display this help command"

  init() {}

  func execute(with context: Context) async throws {
    let registry: REPLCommandRegistry = .shared
    for command in registry.replCanonicalCommands.map({ registry.replCommands[$0]! })
      .filter({ $0.canExecute(with: context) })
      .sorted(by: { $1.name[0] > $0.name[0] })
    {
      context
        .print(
          "  \(command.name[0].padding(toLength: 32, withPad: " ", startingAt: 0)) \(command.summary)"
        )
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}

extension REPLCommand {
  static func canExecute(with context: Context) -> Bool {
    if let type = self as? REPLClassSpecificCommand.Type {
      type.supportedClasses.contains(where: { supportedClass in
        Swift.type(of: context.currentObject).classIdentification
          .isSubclass(of: supportedClass)
      })
    } else {
      true
    }
  }
}

/// The commands the REPL knows. Registration happens once, during initialisation, after which
/// the registry is only read — from the line editor as well as the command task.
final class REPLCommandRegistry: @unchecked Sendable {
  static let shared = REPLCommandRegistry()

  var replCanonicalCommands = Swift.Set<String>()
  var replCommands = [String: REPLCommand.Type]()

  init() {
    register(Help.self)
    register(AddMember.self)
    register(AddPreSharedKey.self)
    register(AddSignalPath.self)
    register(ApplyParamDataSet.self)
    register(ApplyParameterData.self)
    register(ApplyPatch.self)
    register(BeginActiveComponentUpdate.self)
    register(BeginPassiveComponentUpdate.self)
    register(CallMethod.self)
    register(ChangePreSharedKey.self)
    register(ChangePath.self)
    register(ClearCache.self)
    register(ClearDataset.self)
    register(ClearFlag.self)
    register(Connect.self)
    register(ConnectionInfo.self)
    register(ConstructActionObject.self)
    register(ConstructDataset.self)
    register(DeleteActionObject.self)
    register(DeleteMember.self)
    register(DeleteInputPort.self)
    register(DeleteOutputPort.self)
    register(DeleteInputPortClockMapEntry.self)
    register(DeleteOutputPortClockMapEntry.self)
    register(DeletePreSharedKey.self)
    register(DeleteSignalPath.self)
    register(DisableControlSecurity.self)
    register(DeviceInfo.self)
    register(Disconnect.self)
    register(Dump.self)
    register(DumpDataset.self)
    #if DEBUG
    register(DumpSparseRolePathCache.self)
    #endif
    register(DuplicateDataset.self)
    register(EnableControlSecurity.self)
    register(EndUpdateProcess.self)
    register(Exit.self)
    register(FetchCurrentParameterData.self)
    register(FindActionObjectsByLabelRecursive.self)
    register(FindActionObjectsByRole.self)
    register(FindActionObjectsByRoleRecursive.self)
    register(FindDatasets.self)
    register(FindDatasetsRecursive.self)
    register(FirmwareImageContainerUpdate.self)
    register(Flags.self)
    register(Get.self)
    register(GetConnectorStatus.self)
    register(GetDatasetObjectsRecursive.self)
    register(GetDatasetSizes.self)
    register(GetGroupController.self)
    register(GetInputPortName.self)
    register(GetMembers.self)
    register(GetOutputPortName.self)
    register(GetSignalPathRecursive.self)
    register(SetInputPortClockMapEntry.self)
    register(SetOutputPortClockMapEntry.self)
    register(GetSinkConnector.self)
    register(GetSourceConnector.self)
    register(GetEndpoints.self)
    register(GetEndpointCounters.self)
    register(GetSessions.self)
    register(ConfigureConnection.self)
    register(ResetSession.self)
    register(SetStreamingEnabled.self)
    register(ConnectEndpoint.self)
    register(DisconnectEndpoint.self)
    register(GetChannelEndpoints.self)
    register(GetStreamSources.self)
    register(GetNominalMediaClockRate.self)
    register(List.self)
    register(ListObjectNumbers.self)
    register(LoadDataset.self)
    register(LockNoReadWrite.self)
    register(LockNoWrite.self)
    register(PrintWorkingPath.self)
    register(PushPath.self)
    register(PopPath.self)
    register(ResetTimeSource.self)
    register(Resolve.self)
    register(SetFlag.self)
    register(Set.self)
    register(SetInputPortName.self)
    register(SetOutputPortName.self)
    register(SetNominalMediaClockRate.self)
    register(Show.self)
    register(StartUpdateProcess.self)
    register(Statistics.self)
    register(StoreCurrentParamData.self)
    register(Subscribe.self)
    register(Unlock.self)
    register(Up.self)
    register(Unsubscribe.self)
    register(Watch.self)
  }

  func register(_ type: REPLCommand.Type) {
    precondition(!replCanonicalCommands.contains(type.name[0]))
    replCanonicalCommands.insert(type.name[0])
    for name in type.name {
      precondition(replCommands[name] == nil)
      replCommands[name] = type
    }
  }

  func tokenizeCommand(_ command: String) -> [String] {
    replTokenize(command).tokens.map(\.value)
  }

  /// A wrong argument count reads better as the command's usage than as an OCA status.
  struct UsageError: Error, CustomStringConvertible, LocalizedError {
    let summary: String
    var description: String { "usage: \(summary)" }
    var errorDescription: String? { description }
  }

  func command(from arguments: [String], context: Context) async throws -> REPLCommand {
    var arguments = arguments
    guard !arguments.isEmpty else {
      throw Ocp1Error.status(.parameterError)
    }
    guard let type = replCommands[arguments[0]] else {
      throw Ocp1Error.status(.parameterError)
    }

    guard type.canExecute(with: context) else {
      throw Ocp1Error.objectClassMismatch
    }

    arguments.removeFirst()
    let c = type.init()
    let children = Mirror(reflecting: c).children
    var argumentIndex = 0
    let minimumRequiredArguments = (c as? REPLOptionalArguments)?.minimumRequiredArguments

    for child in children {
      guard child.value is any REPLCommandArgumentMarker else { continue }

      if argumentIndex >= arguments.count {
        if let minimumRequiredArguments, arguments.count >= minimumRequiredArguments {
          break
        } else {
          throw UsageError(summary: type.summary)
        }
      }

      let argumentValue = arguments[argumentIndex]

      switch child.value {
      case let value as REPLCommandArgument<String>:
        value.wrappedValue = argumentValue
      case let value as REPLCommandArgument<Bool>:
        value.wrappedValue = NSString(string: argumentValue).boolValue
      case let value as REPLCommandArgument<Int>:
        guard let number = Int(argumentValue) else { throw Ocp1Error.status(.badFormat) }
        value.wrappedValue = number
      case let value as REPLCommandArgument<UInt>:
        guard let number = UInt(argumentValue) else { throw Ocp1Error.status(.badFormat) }
        value.wrappedValue = number
      case let value as REPLCommandArgument<Float>:
        guard let number = Float(argumentValue) else { throw Ocp1Error.status(.badFormat) }
        value.wrappedValue = number
      case let value as REPLCommandArgument<Double>:
        guard let number = Double(argumentValue) else { throw Ocp1Error.status(.badFormat) }
        value.wrappedValue = number
      case let value as REPLCommandArgument<OcaRoot>:
        value.wrappedValue = try await context.resolve(rolePath: argumentValue)
      case let value as REPLCommandArgument<URL>:
        guard let url = URL(string: argumentValue) else { throw Ocp1Error.status(.badFormat) }
        value.wrappedValue = url
      case let value as REPLCommandArgument<Data>:
        value.wrappedValue = try Data(fromHexEncodedString: argumentValue)
      case let value as REPLCommandArgument<[UInt8]>:
        value.wrappedValue = try [UInt8](fromHexEncodedString: argumentValue)
      default:
        throw Ocp1Error.status(.parameterError)
      }

      argumentIndex += 1
    }

    if argumentIndex < arguments.count {
      throw UsageError(summary: type.summary)
    }

    return c
  }

  /// Returns the completions for the word the cursor is on. Each one replaces just that word,
  /// so an argument that is a role path can be completed a component at a time.
  func getCompletions(from line: String, cursor: Int, context: Context) async -> [Completion] {
    let buffer = String(Array(line)[0..<min(cursor, line.count)])
    let (tokens, endsWithSeparator) = replTokenize(buffer)

    let word: REPLToken? = endsWithSeparator ? nil : tokens.last
    let start = word.map { buffer.distance(from: buffer.startIndex, to: $0.start) } ?? cursor
    let partial = word?.value ?? ""

    let candidates: [String]

    if tokens.isEmpty || (tokens.count == 1 && !endsWithSeparator) {
      candidates = replCommands.keys.filter { $0.hasPrefix(partial) }
    } else {
      guard let type = replCommands[tokens[0].value],
            let completions = await type.getCompletions(with: context, currentBuffer: buffer)
      else {
        return []
      }
      candidates = completions.filter { $0.hasPrefix(partial) }
    }

    return candidates.sorted().map {
      Completion(replEscape($0, quoted: word?.isQuoted ?? false), replacing: start..<cursor)
    }
  }
}

protocol REPLStringConvertible: Sendable {
  func replString(context: Context, object: OcaRoot) async -> String
}

extension Array: REPLStringConvertible where Element: REPLStringConvertible {
  func replString(context: Context, object: OcaRoot) async -> String {
    let replStrings = await asyncMap { await $0.replString(context: context, object: object) }
    return String(describing: replStrings)
  }
}

extension Float: REPLStringConvertible {
  func replString(context: Context, object: OcaRoot) async -> String {
    String(format: "%.2f", self)
  }
}

extension Double: REPLStringConvertible {
  func replString(context: Context, object: OcaRoot) async -> String {
    String(format: "%.2f", self)
  }
}

extension OcaBoundedPropertyValue: REPLStringConvertible {
  func replString(context: Context, object: OcaRoot) async -> String {
    if let value = value as? REPLStringConvertible {
      await value.replString(context: context, object: object)
    } else {
      String(describing: value)
    }
  }
}

extension OcaRoot: REPLStringConvertible {
  func replString(context: Context, object: OcaRoot) async -> String {
    if let role = try? await getRole() {
      role
    } else {
      objectNumber.oNoString
    }
  }
}

extension OcaObjectIdentification: REPLStringConvertible {
  func replString(context: Context, object: OcaRoot) async -> String {
    guard let _object = try? await context.connection.resolve(object: self) else {
      return oNo.oNoString
    }
    return await _object.replString(context: context, object: object)
  }
}

func replString(for value: Any, context: Context, object: OcaRoot) async -> String {
  if let value = value as? REPLStringConvertible {
    await value.replString(
      context: context,
      object: context.currentObject
    )
  } else {
    String(describing: value)
  }
}

func replValue(
  for stringValue: String,
  type: Any.Type,
  context: Context,
  object: OcaRoot
) async throws -> Any {
  if let type = type as? REPLStringInitializable.Type {
    return try await type.init(context: context, object: object, stringValue)
  } else if let caseIterableValueType = type as? any CaseIterable.Type,
            let caseIterableValue = caseIterableValueType.value(for: stringValue)
  {
    return caseIterableValue
  } else if let fixedIntegerType = type as? any FixedWidthInteger.Type {
    var exactFixedIntegerValue: (any FixedWidthInteger)?

    if stringValue.lowercased().hasPrefix("0x") {
      if let fixedIntegerValue = UInt(stringValue.dropFirst(2)) {
        exactFixedIntegerValue = fixedIntegerType.init(exactly: fixedIntegerValue)
      }
    } else {
      if let fixedIntegerValue = Int(stringValue) {
        exactFixedIntegerValue = fixedIntegerType.init(exactly: fixedIntegerValue)
      }
    }

    if let exactFixedIntegerValue { return exactFixedIntegerValue }
  }
  throw Ocp1Error.status(.badFormat)
}

protocol REPLStringInitializable: Sendable {
  init(context: Context, object: OcaRoot, _ replString: String) async throws
}

extension Double: REPLStringInitializable {
  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    guard let floatingPointValue = Double(replString) else {
      throw Ocp1Error.status(.badFormat)
    }
    self = floatingPointValue
  }
}

extension String: REPLStringInitializable {
  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    self = replString
  }
}

extension Float: REPLStringInitializable {
  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    guard let floatingPointValue = Float(replString) else {
      throw Ocp1Error.status(.badFormat)
    }
    self = floatingPointValue
  }
}

extension Bool: REPLStringInitializable {
  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    self = NSString(string: replString).boolValue
  }
}

extension OcaObjectIdentification: REPLStringInitializable {
  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    self = try await context.resolve(rolePath: replString).objectIdentification
  }
}

extension Data: REPLStringInitializable {
  init(fromHexEncodedString stringValue: String) throws {
    guard stringValue.lowercased().hasPrefix("0x"),
          let decoded = Data(hex: String(stringValue.dropFirst(2)))
    else { throw Ocp1Error.status(.badFormat) }
    self = decoded
  }

  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    try self.init(fromHexEncodedString: replString)
  }
}

extension [UInt8]: REPLStringInitializable {
  init(fromHexEncodedString stringValue: String) throws {
    self = try Array(Data(fromHexEncodedString: stringValue))
  }

  init(context: Context, object: OcaRoot, _ replString: String) async throws {
    try self.init(fromHexEncodedString: replString)
  }
}

extension CaseIterable {
  static func value(for string: String) -> Any? {
    for aCase in allCases {
      if String(describing: aCase) == string {
        return aCase
      }
    }
    return nil
  }
}

/// https://stackoverflow.com/questions/26501276/converting-hex-string-to-nsdata-in-swift
extension Data {
  init?(hex: String) {
    guard !hex.isEmpty, hex.count.isMultiple(of: 2) else {
      return nil
    }

    let characters = Array(hex)
    let bytes = stride(from: 0, to: characters.count, by: 2).compactMap { index -> UInt8? in
      let digits = String(characters[index..<index + 2])
      guard digits.allSatisfy(\.isHexDigit) else { return nil }
      return UInt8(digits, radix: 16)
    }

    // a pair that did not convert leaves the result shorter than the string it came from
    guard bytes.count == characters.count / 2 else { return nil }

    self.init(bytes)
  }

  var hexString: String {
    map { String(format: "%02hhx", $0) }.joined()
  }
}
