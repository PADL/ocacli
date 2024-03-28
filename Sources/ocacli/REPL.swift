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

private protocol REPLCommandArgumentMarker {}

protocol REPLOptionalArguments {
    var minimumRequiredArguments: Int { get }
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
        self == Help.self || self == Connect.self || self == Exit.self
    }

    var isUsableWhenDisconnected: Bool {
        Self.isUsableWhenDisconnected
    }
}

protocol REPLCurrentBlockCompletable: REPLCommand {}

extension REPLCurrentBlockCompletable {
    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
        context.currentObjectCompletions
    }
}

struct Help: REPLCommand {
    static let name = ["help", "?"]
    static let summary = "Display this help command"

    init() {}

    func execute(with context: Context) async throws {
        for command in REPLCommandRegistry.shared.replCanonicalCommands.sorted() {
            let summary = REPLCommandRegistry.shared.replCommands[command]!.summary
            context
                .print("  \(command.padding(toLength: 21, withPad: " ", startingAt: 0)) \(summary)")
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
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

    // https://stackoverflow.com/questions/42484311/swift-split-string-to-array-with-exclusion
    func tokenizeCommand(_ command: String) -> [String] {
        let pattern = "([^\\s\"]+|\"[^\"]+\")"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let arr = regex.matches(in: command, options: [], range: NSRange(0..<command.utf16.count))
            .map {
                (command as NSString).substring(with: $0.range(at: 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        return arr
    }

    func command(from arguments: [String], context: Context) async throws -> REPLCommand {
        var arguments = arguments
        precondition(arguments.count > 0)
        guard let type = replCommands[arguments[0]] else {
            throw Ocp1Error.status(.parameterError)
        }

        arguments.removeFirst()
        let c = type.init()
        let children = Mirror(reflecting: c).children
        var argumentIndex = 0
        let minimumRequiredArguments = (c as? REPLOptionalArguments)?.minimumRequiredArguments

        for child in children {
            guard child.value is any REPLCommandArgumentMarker else { continue }

            if argumentIndex >= arguments.count {
                if let minimumRequiredArguments, arguments.count <= minimumRequiredArguments {
                    break
                } else {
                    throw Ocp1Error.status(.parameterOutOfRange)
                }
            }

            let argumentValue = arguments[argumentIndex]

            if let value = child.value as? REPLCommandArgument<String> {
                value.wrappedValue = argumentValue
            } else if let value = child.value as? REPLCommandArgument<Bool> {
                value.wrappedValue = NSString(string: argumentValue).boolValue
            } else if let value = child.value as? REPLCommandArgument<any FixedWidthInteger> {
                value.wrappedValue = Int(fromString: argumentValue)
            } else if let value = child.value as? REPLCommandArgument<OcaFloat32> {
                value.wrappedValue = OcaFloat32(fromString: argumentValue)
            } else if let value = child.value as? REPLCommandArgument<OcaRoot> {
                value.wrappedValue = try await context.resolve(rolePath: argumentValue)
            } else {
                throw Ocp1Error.status(.parameterError)
            }

            argumentIndex += 1
        }

        if argumentIndex < arguments.count {
            throw Ocp1Error.status(.parameterOutOfRange)
        }

        return c
    }

    func getCompletions(from buffer: String, context: Context) -> [String]? {
        let tokens = tokenizeCommand(buffer)
        let completions: [String]?

        if tokens.count == 0 {
            completions = nil
        } else if tokens.count == 1, replCommands[tokens[0]] == nil {
            completions = Array(replCommands.keys)
        } else {
            guard let type = replCommands[tokens[0]] else {
                return nil
            }
            let suffixes = type.getCompletions(with: context, currentBuffer: buffer)
            completions = suffixes?.map { "\(tokens[0]) \($0)" }
        }

        return completions
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
            return await value.replString(context: context, object: object)
        } else {
            return String(describing: value)
        }
    }
}

extension OcaRoot: REPLStringConvertible {
    func replString(context: Context, object: OcaRoot) async -> String {
        if let role = try? await getRole() {
            return role
        } else {
            return objectNumber.oNoString
        }
    }
}

extension OcaObjectIdentification: REPLStringConvertible {
    func replString(context: Context, object: OcaRoot) async -> String {
        guard let _object = await context.connection.resolve(object: self) else {
            return oNo.oNoString
        }
        return await _object.replString(context: context, object: object)
    }
}

func replString(for value: Any, context: Context, object: OcaRoot) async -> String {
    if let value = value as? REPLStringConvertible {
        return await value.replString(
            context: context,
            object: context.currentObject
        )
    } else {
        return String(describing: value)
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
    } else if let fixedIntegerType = type as? any FixedWidthInteger.Type,
              let fixedIntegerValue = Int(stringValue),
              let fixedIntegerValue = fixedIntegerType.init(exactly: fixedIntegerValue)
    {
        return fixedIntegerValue
    } else {
        throw Ocp1Error.status(.badFormat)
    }
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

private extension CaseIterable {
    static func value(for string: String) -> Any? {
        for aCase in allCases {
            if String(describing: aCase) == string {
                return aCase
            }
        }
        return nil
    }
}
