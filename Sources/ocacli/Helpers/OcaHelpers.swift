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

private let dumpConcurrency = 8
private let dumpTypeKey = "type"
private let dumpMembersKey = "members"
private let dumpActionObjectsKey = "ActionObjects"

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
      guard let actionObjects = try? actionObjects.asOptionalResult().get() else {
        return nil
      }

      var roles = [(OcaRoot, OcaString)]()

      for actionObject in actionObjects {
        guard let actionObject = connectionDelegate?.resolve(cachedObject: actionObject.oNo),
              let role = try? actionObject.role.asOptionalResult().get()
        else {
          return nil
        }
        roles.append((actionObject, role))
      }

      return roles
    }
  }

  var cachedActionObjectRoles: [(OcaRoot, OcaString)] {
    get async throws {
      guard let actionObjects = try? actionObjects.asOptionalResult().get() else {
        throw Ocp1Error.noInitialValue
      }

      var roles = [(OcaRoot, OcaString)]()

      for actionObject in actionObjects {
        if let actionObject = connectionDelegate?
          .resolve(cachedObject: actionObject.oNo),
          let role = try? actionObject.role.asOptionalResult().get()
        {
          roles.append((actionObject, role))
        }
      }

      return roles
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
    jsonObject[dumpTypeKey] = String(describing: type(of: self))
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
      jsonObject[dumpMembersKey] = await boundedConcurrentMap(
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
    try await JSONSerialization.data(
      withJSONObject: getDumpJsonObject(context: context),
      options: options
    )
  }
}

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
