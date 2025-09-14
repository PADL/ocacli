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

import CommandLineKit
import Foundation
import Logging
import SwiftOCA

enum ContextFlagsNames: Int, CaseIterable {
  /// cache property lookups
  case cacheProperties = 0
  /// subscribe to property events, so properties are updated asynchronously
  case subscribePropertyEvents = 1
  /// connected device supports findActionObjectsByPath() method
  case supportsFindActionObjectsByPath = 2
  case enableRolePathLookupCache = 3
  case refreshDeviceTreeOnConnection = 4
  case automaticReconnect = 5
  case enableTracing = 6

  init?(fromString string: String) {
    for flag in Self.allCases {
      if String(describing: flag) == string {
        self = flag
        return
      }
    }

    return nil
  }

  static var allCaseNames: [String] {
    allCases.map { String(describing: $0) }
  }
}

struct ContextFlags: OptionSet, ConvertibleFromString {
  init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  init(_ contextFlagsNames: ContextFlagsNames) {
    self.init(rawValue: 1 << contextFlagsNames.rawValue)
  }

  var rawValue: UInt32

  typealias RawValue = UInt32

  static let cacheProperties = ContextFlags(ContextFlagsNames.cacheProperties)
  static let subscribePropertyEvents = ContextFlags(ContextFlagsNames.subscribePropertyEvents)
  static let supportsFindActionObjectsByPath = ContextFlags(
    ContextFlagsNames
      .supportsFindActionObjectsByPath
  )
  static let enableRolePathLookupCache = ContextFlags(ContextFlagsNames.enableRolePathLookupCache)
  static let refreshDeviceTreeOnConnection = ContextFlags(
    ContextFlagsNames
      .refreshDeviceTreeOnConnection
  )
  static let automaticReconnect = ContextFlags(ContextFlagsNames.automaticReconnect)
  static let enableTracing = ContextFlags(ContextFlagsNames.enableTracing)

  init?(fromString string: String) {
    guard let flagName = ContextFlagsNames(fromString: string) else { return nil }
    self.init(flagName)
  }

  var connectionFlags: Ocp1ConnectionFlags {
    var flags = Ocp1ConnectionFlags()

    if contains(.automaticReconnect) {
      flags.insert(.automaticReconnect)
    }
    if contains(.refreshDeviceTreeOnConnection) {
      flags.insert(.refreshDeviceTreeOnConnection)
    }
    if contains(.enableTracing) {
      flags.insert(.enableTracing)
    }
    if contains(.subscribePropertyEvents), contains(.automaticReconnect) {
      flags.insert(.refreshSubscriptionsOnReconnection)
    }
    return flags
  }

  var propertyResolutionFlags: OcaPropertyResolutionFlags {
    var flags = OcaPropertyResolutionFlags()

    if contains(.cacheProperties) {
      flags.formUnion([.cacheValue, .throwCachedError, .cacheErrors, .returnCachedValue])
    }
    if contains(.subscribePropertyEvents) {
      flags.formUnion([.subscribeEvents])
    }
    return flags
  }

  var cachedPropertyResolutionFlags: OcaPropertyResolutionFlags {
    propertyResolutionFlags.union([.returnCachedValue])
  }
}

enum DeviceEndpointInfo {
  case tcp(String, UInt16)
  case udp(String, UInt16)
  case path(String)

  var hostname: String? {
    switch self {
    case let .tcp(hostname, _):
      hostname
    case let .udp(hostname, _):
      hostname
    case .path:
      nil
    }
  }

  var port: UInt16 {
    switch self {
    case let .tcp(_, port):
      port
    case let .udp(_, port):
      port
    case .path:
      0
    }
  }

  var path: String? {
    switch self {
    case let .path(path):
      path
    default:
      nil
    }
  }

  func getConnection(options: Ocp1ConnectionOptions) async throws -> Ocp1Connection {
    switch self {
    case .tcp:
      fallthrough
    case .udp:
      return try await getRemoteConnection(options: options)
    case .path:
      return try await getLocalConnection(options: options)
    }
  }

  private func getRemoteConnection(options: Ocp1ConnectionOptions) async throws
    -> Ocp1Connection
  {
    var connection: Ocp1Connection?
    guard let hostname else {
      throw Ocp1Error.serviceResolutionFailed
    }
    let host = Host(name: hostname)
    var savedError: Error?

    for hostAddress in host.addresses {
      do {
        var deviceAddressData = Data()
        if hostAddress.contains(":") {
          var deviceAddress = try sockaddr_in6(hostAddress, port: port)
          withUnsafeBytes(of: &deviceAddress) { bytes in
            deviceAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
          }
        } else {
          var deviceAddress = try sockaddr_in(hostAddress, port: port)
          withUnsafeBytes(of: &deviceAddress) { bytes in
            deviceAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
          }
        }
        if case .udp = self {
          connection = try await Ocp1UDPConnection(
            deviceAddress: deviceAddressData,
            options: options
          )
        } else {
          connection = try await Ocp1TCPConnection(
            deviceAddress: deviceAddressData,
            options: options
          )
        }
        if let connection {
          try await connection.connect()
          break
        }
      } catch {
        savedError = error
      }
    }

    if let connection {
      return connection
    } else if let savedError {
      throw savedError
    } else {
      throw Ocp1Error.serviceResolutionFailed
    }
  }

  private func getLocalConnection(options: Ocp1ConnectionOptions) async throws -> Ocp1Connection {
    let connection = try await Ocp1TCPConnection(path: path!, options: options)
    try await connection.connect()
    return connection
  }
}

final class Context: @unchecked Sendable {
  let connection: Ocp1Connection
  let logger: Logger

  // the following variables should only be mutated by the command sink (the async task)
  var contextFlags: ContextFlags
  var subscriptions = [OcaONo: Ocp1Connection.SubscriptionCancellable]()

  // the following variables can be read by the command source (the event loop)
  private(set) var currentObject: OcaRoot
  private(set) var currentObjectCompletions: [String]? = []
  private var currentObjectPath: OcaNamePath? = [""]
  fileprivate var sparseRolePathCache: [OcaNamePath: OcaRoot] = [:]

  init(
    deviceEndpointInfo: DeviceEndpointInfo,
    contextFlags: ContextFlags,
    logger: Logger,
    connectionTimeout: Duration? = nil,
    responseTimeout: Duration? = nil
  ) async throws {
    self.contextFlags = contextFlags
    self.logger = logger
    connection = try await deviceEndpointInfo
      .getConnection(options: Ocp1ConnectionOptions(
        flags: self.contextFlags.connectionFlags,
        connectionTimeout: connectionTimeout ?? .seconds(2),
        responseTimeout: responseTimeout ?? .seconds(2)
      ))
    currentObject = await connection.rootBlock
    try await changeCurrentPath(to: connection.rootBlock)
  }

  func finish() async {
    try? await connection.disconnect()
  }

  func findObjectCached(
    rolePath path: OcaNamePath,
    relativeTo baseObject: OcaBlock
  ) async throws -> OcaRoot {
    precondition(contextFlags.contains(.enableRolePathLookupCache))

    var object: OcaRoot! = baseObject
    for pathComponent in path {
      guard let block = object as? OcaBlock else {
        throw Ocp1Error.objectClassMismatch
      }

      var childObject: OcaRoot?

      for role in try await block.cachedActionObjectRoles {
        if role.1 == pathComponent {
          childObject = role.0
          break
        }
      }

      guard let childObject else {
        throw Ocp1Error.objectNotPresent(OcaInvalidONo)
      }

      object = childObject
    }

    guard let object else { throw Ocp1Error.objectNotPresent(OcaInvalidONo) }
    return object
  }

  private static func findObjectFallback(
    with rolePath: OcaNamePath,
    relativeTo baseObject: OcaBlock
  ) async throws -> OcaRoot {
    var object: OcaRoot! = baseObject
    for pathComponent in rolePath {
      guard let block = object as? OcaBlock else {
        throw Ocp1Error.objectClassMismatch
      }

      var childObject: OcaRoot?

      for actionObject in try await block.resolveActionObjects() {
        let role = try await actionObject.getRole()
        if role == pathComponent {
          childObject = actionObject
          break
        }
      }

      guard let childObject else {
        throw Ocp1Error.objectNotPresent(OcaInvalidONo)
      }

      object = childObject
    }

    guard let object else { throw Ocp1Error.objectNotPresent(OcaInvalidONo) }
    return object
  }

  private static func findObject(
    with rolePath: OcaNamePath,
    relativeTo baseObject: OcaBlock
  ) async throws -> (OcaObjectIdentification, OcaString) {
    let flags =
      OcaActionObjectSearchResultFlags([.oNo, .classIdentification, .containerPath, .role])
    let searchResult = try await baseObject.find(
      actionObjectsByPath: rolePath,
      resultFlags: flags
    )

    guard searchResult.count == 1, let oNo = searchResult[0].oNo else {
      throw Ocp1Error.status(.processingFailed)
    }
    guard let role = searchResult[0].role,
          let classIdentification = searchResult[0].classIdentification
    else {
      throw Ocp1Error.objectNotPresent(oNo)
    }

    return (OcaObjectIdentification(
      oNo: oNo,
      classIdentification: classIdentification
    ), role)
  }

  private func resolve(
    rolePath path: OcaNamePath,
    relativeTo baseObject: OcaBlock
  ) async throws -> OcaRoot? {
    var object: OcaRoot?

    if contextFlags.contains(.enableRolePathLookupCache) {
      if contextFlags.contains(.supportsFindActionObjectsByPath) {
        object = sparseRolePathCache[path]
      }

      if object == nil {
        do {
          object = try await findObjectCached(rolePath: path, relativeTo: baseObject)
        } catch Ocp1Error.objectNotPresent, Ocp1Error.noInitialValue {}
      }
    }

    if object == nil, contextFlags.contains(.supportsFindActionObjectsByPath) {
      do {
        let objectIdentificationAndRole = try await Context.findObject(
          with: path,
          relativeTo: baseObject
        )
        object = try? await connection.resolve(object: objectIdentificationAndRole.0)

        /// sparseRolePathCache is used to cache results of FindActionObjectsByPath()
        /// where we haven't necessarily traversed the complete object hierarchy
        if let object {
          object.cacheRole(objectIdentificationAndRole.1)
          sparseRolePathCache[path] = object
        }
      } catch Ocp1Error.status(.notImplemented) {
        contextFlags.remove(.supportsFindActionObjectsByPath)
      }
    }

    if object == nil {
      object = try await Context.findObjectFallback(
        with: path,
        relativeTo: baseObject
      )
    }

    return object
  }

  func resolve<T: OcaRoot>(rolePath path: String) async throws -> T {
    let object: OcaRoot?

    if let oNo = OcaONo(oNoString: path) {
      object = try await connection.resolve(objectOfUnknownClass: oNo)
    } else if path == "." {
      object = currentObject
    } else if path == ".." {
      if let currentObject = currentObject as? OcaOwnable {
        let owner = try await currentObject
          .getOwner(flags: contextFlags.cachedPropertyResolutionFlags)
        object = try await connection
          .resolve(object: OcaObjectIdentification(
            oNo: owner,
            classIdentification: OcaBlock.classIdentification
          ))
      } else {
        object = await connection.rootBlock
      }
    } else {
      let pathComponents = path.pathComponents
      let baseObject = await pathComponents.1 ? connection.rootBlock : currentObject

      if pathComponents.0.isEmpty {
        object = baseObject
      } else if let baseObject = baseObject as? OcaBlock {
        object = try await resolve(rolePath: pathComponents.0, relativeTo: baseObject)
      } else {
        throw Ocp1Error.objectClassMismatch
      }
    }
    guard let object else {
      throw Ocp1Error.objectNotPresent(OcaInvalidONo)
    }
    guard let object = object as? T else {
      throw Ocp1Error.objectClassMismatch
    }
    return object
  }

  func changeCurrentPath(to rolePath: String) async throws {
    if rolePath.isEmpty { return }
    let object: OcaBlock = try await resolve(rolePath: rolePath)
    try await changeCurrentPath(to: object)
  }

  private func _resolveObjectCompletions(
    _ object: OcaRoot,
    path: OcaNamePath
  ) async throws -> [String]? {
    guard let object = object as? OcaBlock else { return nil }
    var currentObjectCompletions: [String]?
    currentObjectCompletions = try? await object.cachedActionObjectRoles.map { _, role in
      pathComponentsToPathString([role], absolute: false, escaping: true)
    }
    currentObjectCompletions?.append(contentsOf: sparseRolePathCache.keys.filter {
      $0.count > path.count && Array($0.prefix(path.count)) == path
    }.map { pathComponentsToPathString([$0[path.count]], absolute: false, escaping: true) })
    return currentObjectCompletions
  }

  func refreshCurrentObjectCompletions() async {
    if let currentObjectPath {
      currentObjectCompletions = try? await _resolveObjectCompletions(
        currentObject,
        path: currentObjectPath
      )
    } else {
      currentObjectCompletions = nil
    }
  }

  private var pathStack = [OcaRoot]()

  func pushPath(_ object: OcaRoot) async throws {
    pathStack.append(currentObject)
    try await changeCurrentPath(to: object)
  }

  func popPath() async throws {
    guard let lastObject = pathStack.popLast() else {
      throw Ocp1Error.noInitialValue
    }
    try await changeCurrentPath(to: lastObject)
  }

  func changeCurrentPath(to object: OcaRoot) async throws {
    do {
      currentObjectPath = try await object
        .getRolePath(flags: contextFlags.cachedPropertyResolutionFlags)
    } catch Ocp1Error.objectClassMismatch {
      let rolePathString = try await object
        .getRolePathString(flags: contextFlags.cachedPropertyResolutionFlags)
      currentObjectPath = [rolePathString]
    }
    currentObject = object
    await refreshCurrentObjectCompletions()
  }

  var currentPathString: String {
    if let currentObjectPath {
      currentObjectPath.pathString
    } else {
      currentObject.objectNumber.oNoString
    }
  }

  let lock = NSRecursiveLock()

  func print(_ items: Any...) {
    lock.lock()
    defer { lock.unlock() }
    Swift.print(items, separator: " ", terminator: "\n")
  }

  @Sendable
  func onPropertyEvent(event: OcaEvent, eventData data: Data) {
    let decoder = Ocp1Decoder()
    guard let propertyID = try? decoder.decode(
      OcaPropertyID.self,
      from: data
    ) else { return }

    Task {
      let emitter = await connection.resolve(cachedObject: event.emitterONo)
      let emitterPath: String = if let emitter {
        try await emitter
          .getRolePathString(flags: contextFlags.cachedPropertyResolutionFlags)
      } else {
        event.emitterONo.oNoString
      }
      logger.info(
        "event \(event.eventID) from \(emitterPath) property \(propertyID) data \(data)"
      )
    }
  }
}

#if DEBUG
struct DumpSparseRolePathCache: REPLCommand {
  static let name = ["dump-sparse-role-path-cache"]
  static let summary = "Dump spare role path cache"

  init() {}

  func execute(with context: Context) async throws {
    for item in context.sparseRolePathCache {
      context.print("\(item.key): \(item.value)")
    }
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
#endif
