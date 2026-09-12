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
@_spi(SwiftOCAPrivate) import SwiftOCA

private let dumpConcurrency = 8
private let dumpActionObjectsKey = "ActionObjects"
private let dumpObjectNumberKey = "ONo"

private func boundedConcurrentMap<Element: Sendable, Value: Sendable>(
  _ elements: [Element],
  maxConcurrentTasks: Int,
  _ transform: @Sendable @escaping (Element) async -> Value
) async -> [Value] {
  let concurrency = max(1, maxConcurrentTasks)

  return await withTaskGroup(of: (Int, Value).self, returning: [Value].self) { taskGroup in
    var iterator = elements.enumerated().makeIterator()
    var results = [Value?](repeating: nil, count: elements.count)

    for _ in 0..<min(concurrency, elements.count) {
      guard let (index, element) = iterator.next() else { break }
      taskGroup.addTask {
        await (index, transform(element))
      }
    }

    while let (index, value) = await taskGroup.next() {
      results[index] = value

      if let (nextIndex, nextElement) = iterator.next() {
        taskGroup.addTask {
          await (nextIndex, transform(nextElement))
        }
      }
    }

    return results.compactMap { $0 }
  }
}

@OcaConnection
extension OcaBlock {
  /// The roles of every action object, or nil if any of them is missing from the cache.
  ///
  /// Unlike `cachedActionObjectRoles` this will not answer with a part of the block: a caller
  /// listing what is in a block would otherwise be told about whichever objects happen to have
  /// been resolved, and take that for all of them.
  var completeCachedActionObjectRoles: [(OcaRoot, OcaString)]? {
    get async throws {
      guard let actionObjects = try? actionObjects.asOptionalResult().get(),
            let roles = try? await cachedActionObjectRoles,
            roles.count == actionObjects.count
      else {
        return nil
      }

      return roles
    }
  }

  var cachedActionObjectRoles: [(OcaRoot, OcaString)] {
    get async throws {
      guard let actionObjects = try? actionObjects.asOptionalResult().get() else {
        throw Ocp1Error.noInitialValue
      }

      return actionObjects.compactMap { actionObject in
        guard let object = connectionDelegate?.resolve(cachedObject: actionObject.oNo),
              let role = try? object.role.asOptionalResult().get()
        else {
          return nil
        }

        return (object, role)
      }
    }
  }
}

@OcaConnection
extension OcaRoot {
  private func getDumpPropertyJsonObject(context: Context) async -> [String: any Sendable] {
    guard self is OcaWorker else {
      return [:]
    }

    let flags = context.contextFlags.cachedPropertyResolutionFlags
    let properties = await Array(allPropertyKeyPaths)
    let propertyEntries = await boundedConcurrentMap(
      properties,
      maxConcurrentTasks: dumpConcurrency
    ) { propertyEntry in
      let property = self[keyPath: propertyEntry.value] as! any OcaPropertyRepresentable
      return await (try? property.getJsonValue(self, keyPath: propertyEntry.value, flags: flags)) ??
        [:]
    }

    var jsonObject = propertyEntries.reduce(into: [String: any Sendable]()) { result, value in
      result.merge(value) { _, new in new }
    }
    return jsonObject
  }

  /// Every property's getter response, as the device wrote it, merged into one object.
  ///
  /// OCP.2 responses are JSON with the device's own member names, so taking them verbatim
  /// shows what the device said rather than what the class model can decode: a member our
  /// datatype does not have survives, under the spelling the device used for it.
  private func getRawDumpPropertyJsonObject() async -> [String: any Sendable] {
    guard self is OcaWorker else {
      return [:]
    }

    // the object number is ours, but the class is the device's answer, which can name a
    // subclass we do not model (and whose extra properties we cannot ask for)
    var identity: [String: any Sendable] = [dumpObjectNumberKey: objectNumber]
    await identity.merge(getRawClassIdentification()) { _, new in new }

    let properties = await Array(allPropertyKeyPaths)
    let responses = await boundedConcurrentMap(
      properties,
      maxConcurrentTasks: dumpConcurrency
    ) { propertyEntry in
      // a property without a getter, or one the device refuses, contributes nothing
      await (try? self.getPropertyResponseParameters(keyPath: propertyEntry.value)) ??
        Ocp1Parameters()
    }

    return responses.reduce(into: identity) { result, parameters in
      guard let object = parameters.ocp2SendableParameters else { return }
      result.merge(object) { _, new in new }
    }
  }

  /// The device's own `GetClassIdentification` response, or nothing if it will not answer.
  private func getRawClassIdentification() async -> [String: any Sendable] {
    guard let response = try? await sendCommandRrq(
      methodID: OcaMethodID("1.1"),
      parameters: Ocp1Parameters()
    ), response.statusCode == .ok,
    let object = response.parameters.ocp2SendableParameters
    else {
      return [:]
    }
    return object
  }

  private func getRawDumpJsonObject(context: Context) async -> [String: any Sendable] {
    // a matrix's members are assembled from GetMembers rather than returned by a property
    // getter, so a matrix is dumped through the class model whatever the protocol
    if self is OcaMatrix {
      return await getDumpJsonObject(context: context)
    }

    var jsonObject = await getRawDumpPropertyJsonObject()

    guard let block = self as? OcaBlock else {
      return jsonObject
    }

    // the device's own member list stays as it sent it, under whichever name it used; the
    // children are resolved alongside it, as a dump is recursive
    if let members = try? await block.resolveActionObjects() {
      jsonObject[dumpActionObjectsKey] = await boundedConcurrentMap(
        members,
        maxConcurrentTasks: dumpConcurrency
      ) { member in
        await member.getRawDumpJsonObject(context: context)
      }
    }

    return jsonObject
  }

  private func getDumpJsonObject(context: Context) async -> [String: any Sendable] {
    if let matrix = self as? OcaMatrix {
      return await matrix.getJsonValue(flags: context.contextFlags.cachedPropertyResolutionFlags)
    }

    var jsonObject = await getDumpPropertyJsonObject(context: context)

    guard let block = self as? OcaBlock else {
      return jsonObject
    }

    jsonObject.removeValue(forKey: dumpActionObjectsKey)

    if let members = try? await block.resolveActionObjects() {
      jsonObject[dumpActionObjectsKey] = await boundedConcurrentMap(
        members,
        maxConcurrentTasks: dumpConcurrency
      ) { member in
        await member.getDumpJsonObject(context: context)
      }
    }

    return jsonObject
  }

  func getJsonRepresentation(
    context: Context,
    options: JSONSerialization.WritingOptions
  ) async throws -> Data {
    // on OCP.2 the device speaks JSON itself, so dump what it sent rather than what the
    // class model could decode and re-encode
    let jsonObject = if context.connection.controlProtocol == .ocp2 {
      await getRawDumpJsonObject(context: context)
    } else {
      await getDumpJsonObject(context: context)
    }
    #if canImport(Darwin)
    // an invalid value aborts inside Darwin's NSJSONSerialization rather than
    // throwing as corelibs does, so refuse it here — naming the offenders,
    // which the ObjC exception would not have done either
    guard JSONSerialization.isValidJSONObject(jsonObject) else {
      throw JsonRepresentationError(offendingPaths: invalidJsonPaths(in: jsonObject))
    }
    #endif
    return try JSONSerialization.data(withJSONObject: jsonObject, options: options)
  }
}

#if canImport(Darwin)
/// The key paths of values `JSONSerialization` cannot represent: non-finite
/// numbers, or types outside the JSON model.
private func invalidJsonPaths(in value: Any, at path: String = "") -> [String] {
  switch value {
  case let dictionary as [String: Any]:
    dictionary.flatMap { invalidJsonPaths(in: $0.value, at: "\(path)/\($0.key)") }
  case let array as [Any]:
    array.enumerated().flatMap { invalidJsonPaths(in: $0.element, at: "\(path)[\($0.offset)]") }
  case let number as NSNumber:
    number.doubleValue.isFinite ? [] : [path]
  case is String, is NSNull:
    []
  default:
    [path]
  }
}

private struct JsonRepresentationError: Error, CustomStringConvertible {
  let offendingPaths: [String]

  var description: String {
    if offendingPaths.isEmpty {
      "object has one or more values that cannot be represented in JSON"
    } else {
      "values cannot be represented in JSON at: " + offendingPaths.joined(separator: ", ")
    }
  }
}
#endif

let ocaPathSeparator: Character = "/"

func pathComponentsToPathString(
  _ path: OcaNamePath,
  absolute: Bool = true
) -> String {
  (absolute ? String(ocaPathSeparator) : "") + path
    .joined(separator: String(ocaPathSeparator))
}

extension [String] {
  var pathString: String {
    pathComponentsToPathString(self)
  }
}

extension String {
  /// Splits a role path into its components and a flag indicating whether it is absolute.
  /// Empty components are elided, so that leading, trailing and repeated separators are all
  /// tolerated (`/Foo/Bar/` resolves the same object as `/Foo/Bar`).
  var pathComponents: ([String], Bool) {
    let absolute = first == ocaPathSeparator
    let namePath = OcaNamePath(
      components(separatedBy: String(ocaPathSeparator))
        .filter { !$0.isEmpty }
    )
    return (namePath, absolute)
  }
}
