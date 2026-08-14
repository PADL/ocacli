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
  static func getCompletions(with context: Context, currentBuffer: String) -> [String]?
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
  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
    context.completions(forPartialRolePath: currentBuffer.replFinalWord)
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

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
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

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
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

final class REPLCommandRegistry {
  static let shared = REPLCommandRegistry()

  var replCanonicalCommands = Swift.Set<String>()
  var replCommands = [String: REPLCommand.Type]()

  init() {
    register(Help.self)
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
          throw Ocp1Error.status(.parameterOutOfRange)
        }
      }

      let argumentValue = arguments[argumentIndex]

      switch child.value {
      case let value as REPLCommandArgument<String>:
        value.wrappedValue = argumentValue
      case let value as REPLCommandArgument<Bool>:
        value.wrappedValue = NSString(string: argumentValue).boolValue
      case let value as REPLCommandArgument<Int>:
        value.wrappedValue = Int(fromString: argumentValue)
      case let value as REPLCommandArgument<UInt>:
        value.wrappedValue = UInt(fromString: argumentValue)
      case let value as REPLCommandArgument<Float>:
        value.wrappedValue = Float(fromString: argumentValue)
      case let value as REPLCommandArgument<Double>:
        value.wrappedValue = Double(fromString: argumentValue)
      case let value as REPLCommandArgument<OcaRoot>:
        value.wrappedValue = try await context.resolve(rolePath: argumentValue)
      case let value as REPLCommandArgument<URL>:
        value.wrappedValue = URL(string: argumentValue)
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
      throw Ocp1Error.status(.parameterOutOfRange)
    }

    return c
  }

  /// Returns the complete command lines that `buffer` could be expanded to, by replacing the
  /// word the cursor is on. The word is replaced rather than appended to, so that arguments
  /// which are role paths can be completed one component at a time.
  func getCompletions(from buffer: String, context: Context) -> [String]? {
    let (tokens, endsWithSeparator) = replTokenize(buffer)

    let word: REPLToken? = endsWithSeparator ? nil : tokens.last
    let prefix = buffer[buffer.startIndex..<(word?.start ?? buffer.endIndex)]
    let partial = word?.value ?? ""

    let completions: [String]

    if tokens.isEmpty || (tokens.count == 1 && !endsWithSeparator) {
      completions = replCommands.keys.filter { $0.hasPrefix(partial) }
    } else {
      guard let type = replCommands[tokens[0].value],
            let suffixes = type.getCompletions(with: context, currentBuffer: buffer)
      else {
        return nil
      }
      completions = suffixes.filter { $0.hasPrefix(partial) }
    }

    return completions.sorted().map { prefix + replEscape($0, quoted: word?.isQuoted ?? false) }
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

// https://stackoverflow.com/questions/26501276/converting-hex-string-to-nsdata-in-swift
extension Data {
  init?(hex: String) {
    guard hex.count.isMultiple(of: 2) else {
      return nil
    }

    let chars = hex.map { $0 }
    let bytes = stride(from: 0, to: chars.count, by: 2)
      .map { String(chars[$0]) + String(chars[$0 + 1]) }
      .compactMap { UInt8($0, radix: 16) }

    guard bytes.count > 0 else { return nil }
    guard hex.count / bytes.count == 2 else { return nil }
    self.init(bytes)
  }

  var hexString: String {
    map { String(format: "%02hhx", $0) }.joined()
  }
}
