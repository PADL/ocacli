//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

import ArgumentParser
import AsyncLineReader
import Foundation
import Logging
import SwiftOCA
import SwiftOCASecure
import struct SystemPackage.Errno

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
  /// connected device supports findActionObjectsByRole() method
  case supportsFindActionObjectsByRole = 7

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

struct ContextFlags: OptionSet, ExpressibleByArgument {
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
  static let supportsFindActionObjectsByRole = ContextFlags(
    ContextFlagsNames
      .supportsFindActionObjectsByRole
  )

  init?(fromString string: String) {
    guard let flagName = ContextFlagsNames(fromString: string) else { return nil }
    self.init(flagName)
  }

  init?(argument: String) {
    self.init(fromString: argument)
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
  case webSocket(String, UInt16)
  case path(String)
  case datagramPath(String)
  #if canImport(Darwin)
  case machPort(String)
  #endif
  case tls(String, UInt16, Ocp1TLSCredential, Ocp1TLSTrustRoots?, Ocp1TLSRevocationOptions)
  case dtls(String, UInt16, Ocp1TLSCredential, Ocp1TLSTrustRoots?, Ocp1TLSRevocationOptions)

  var isDatagram: Bool {
    switch self {
    case .tcp:
      fallthrough
    case .webSocket:
      fallthrough
    case .tls:
      fallthrough
    case .path:
      false
    case .udp:
      fallthrough
    case .datagramPath:
      fallthrough
    case .dtls:
      true
    #if canImport(Darwin)
    case .machPort:
      false
    #endif
    }
  }

  var hostname: String? {
    switch self {
    case let .tcp(hostname, _):
      hostname
    case let .udp(hostname, _):
      hostname
    case let .webSocket(hostname, _):
      hostname
    case let .tls(hostname, _, _, _, _):
      hostname
    case let .dtls(hostname, _, _, _, _):
      hostname
    case .path:
      nil
    case .datagramPath:
      nil
    #if canImport(Darwin)
    case .machPort:
      nil
    #endif
    }
  }

  var port: UInt16 {
    switch self {
    case let .tcp(_, port):
      port
    case let .udp(_, port):
      port
    case let .webSocket(_, port):
      port
    case let .tls(_, port, _, _, _):
      port
    case let .dtls(_, port, _, _, _):
      port
    case .path:
      0
    case .datagramPath:
      0
    #if canImport(Darwin)
    case .machPort:
      0
    #endif
    }
  }

  var path: String? {
    switch self {
    case let .path(path):
      path
    case let .datagramPath(path):
      path
    #if canImport(Darwin)
    case let .machPort(serviceName):
      serviceName
    #endif
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
    case .webSocket:
      return try await getWebSocketConnection(options: options)
    case .path:
      return try await getLocalConnection(options: options)
    case .datagramPath:
      return try await getLocalConnection(options: options)
    #if canImport(Darwin)
    case let .machPort(serviceName):
      return try await getMachPortConnection(serviceName: serviceName, options: options)
    #endif
    case let .tls(_, _, credential, trustRoots, revocation):
      return try await getTLSConnection(
        credential: credential,
        trustRoots: trustRoots,
        revocation: revocation,
        options: options
      )
    case let .dtls(_, _, credential, trustRoots, revocation):
      return try await getDTLSConnection(
        credential: credential,
        trustRoots: trustRoots,
        revocation: revocation,
        options: options
      )
    }
  }

  #if canImport(Darwin)
  @OcaConnection
  private func getMachPortConnection(
    serviceName: String,
    options: Ocp1ConnectionOptions
  ) async throws -> Ocp1Connection {
    let connection = Ocp1MachPortConnection(serviceName: serviceName, options: options)
    try await connection.connect()
    return connection
  }
  #endif

  #if os(macOS) || os(iOS)
  private func getWebSocketConnection(options: Ocp1ConnectionOptions) async throws
    -> Ocp1Connection
  {
    guard let hostname else {
      throw Ocp1Error.serviceResolutionFailed
    }
    let url = URL(string: "ws://\(hostname):\(port)/")!
    let connection = await Ocp1FlyingFoxConnection(url: url, options: options)
    try await connection.connect()
    return connection
  }
  #else
  private func getWebSocketConnection(options: Ocp1ConnectionOptions) async throws
    -> Ocp1Connection
  {
    throw Ocp1Error.serviceResolutionFailed
  }
  #endif

  private func getRemoteConnection(options: Ocp1ConnectionOptions) async throws
    -> Ocp1Connection
  {
    guard let hostname else {
      throw Ocp1Error.serviceResolutionFailed
    }
    // SwiftOCA resolves the hostname (to its candidate addresses, in preference
    // order) on each connect attempt, so pass it through directly rather than
    // resolving here.
    let connection: Ocp1Connection = if isDatagram {
      try await Ocp1UDPConnection(host: hostname, port: port, options: options)
    } else {
      try await Ocp1TCPConnection(host: hostname, port: port, options: options)
    }
    try await connection.connect()
    return connection
  }

  // SwiftOCASecure has a TLS transport where the platform brings one: Network.framework on
  // Apple's, OpenSSL and io_uring on Linux. Windows has neither, so there is nothing here to
  // connect with, and --tls is refused before it gets this far.
  #if canImport(Darwin) || os(Linux)
  private func getTLSConnection(
    credential: Ocp1TLSCredential,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions
  ) async throws -> Ocp1Connection {
    guard let hostname else {
      throw Ocp1Error.serviceResolutionFailed
    }
    // SwiftOCA resolves the hostname on each connect attempt and uses it as the
    // TLS server name (SNI / certificate verification); the optional trustRoots
    // re-roots trust evaluation at a private CA bundle.
    let connection = try await Ocp1TLSStreamConnection(
      host: hostname,
      port: port,
      credential: credential,
      trustRoots: trustRoots,
      revocation: revocation,
      options: options
    )
    try await connection.connect()
    return connection
  }

  /// DTLS-over-UDP variant of `getTLSConnection`.
  private func getDTLSConnection(
    credential: Ocp1TLSCredential,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions
  ) async throws -> Ocp1Connection {
    guard let hostname else {
      throw Ocp1Error.serviceResolutionFailed
    }
    let connection = try await Ocp1TLSDatagramConnection(
      host: hostname,
      port: port,
      credential: credential,
      trustRoots: trustRoots,
      revocation: revocation,
      options: options
    )
    try await connection.connect()
    return connection
  }
  #else
  private func getTLSConnection(
    credential: Ocp1TLSCredential,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions
  ) async throws -> Ocp1Connection {
    throw Ocp1Error.notImplemented
  }

  private func getDTLSConnection(
    credential: Ocp1TLSCredential,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions
  ) async throws -> Ocp1Connection {
    throw Ocp1Error.notImplemented
  }
  #endif

  private func getLocalConnection(options: Ocp1ConnectionOptions) async throws -> Ocp1Connection {
    guard let path else {
      throw Ocp1Error.serviceResolutionFailed
    }
    #if canImport(IORing)
    let connection: Ocp1Connection = if isDatagram {
      try await Ocp1IORingDomainSocketDatagramConnection(path: path, options: options)
    } else {
      try await Ocp1TCPConnection(path: path, options: options)
    }
    #else
    guard !isDatagram else { throw Errno.addressFamilyNotSupported }
    let connection = try await Ocp1TCPConnection(path: path, options: options)
    #endif
    try await connection.connect()
    return connection
  }
}

final class Context: @unchecked Sendable {
  let connection: Ocp1Connection
  let logger: Logger
  /// the line editor, when there is one, so that a command can be interrupted from the keyboard
  var lineReader: AsyncLineReader.LineReader?

  // the following variables should only be mutated by the command sink (the async task)
  var contextFlags: ContextFlags
  var subscriptions = [OcaONo: Ocp1Connection.SubscriptionCancellable]()

  // the following variables can be read by the command source (the event loop)
  private(set) var currentObject: OcaRoot
  private var currentObjectPath: OcaNamePath? = [""]
  fileprivate var sparseRolePathCache: [OcaNamePath: OcaRoot] = [:]

  init(
    deviceEndpointInfo: DeviceEndpointInfo,
    contextFlags: ContextFlags,
    logger: Logger,
    connectionTimeout: Duration? = nil,
    responseTimeout: Duration? = nil,
    batchSize: UInt32? = nil,
    batchThreshold: Duration? = nil,
    insecure: Bool = false
  ) async throws {
    self.contextFlags = contextFlags
    self.logger = logger
    let batchingOptions = try Ocp1ConnectionOptions.BatchingOptions(
      batchSize: batchSize,
      batchThreshold: batchThreshold
    )
    var connectionFlags = self.contextFlags.connectionFlags
    if insecure { connectionFlags.insert(.disableCertificateVerification) }
    connection = try await deviceEndpointInfo
      .getConnection(options: Ocp1ConnectionOptions(
        flags: connectionFlags,
        connectionTimeout: connectionTimeout ?? .seconds(2),
        responseTimeout: responseTimeout ?? .seconds(2),
        batchingOptions: batchingOptions
      ))
    currentObject = await connection.rootBlock
    try await changeCurrentPath(to: connection.rootBlock)
  }

  var isDatagram: Bool {
    get async {
      await connection.isDatagram
    }
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

        // sparseRolePathCache is used to cache results of FindActionObjectsByPath()
        // where we haven't necessarily traversed the complete object hierarchy
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

  /// Resolves `.` and `..` components lexically. Relative paths containing them are rebased on
  /// the current object path, which is only possible if it is known; otherwise the components
  /// are left alone and resolution will fail as it did before.
  private func _normalize(_ pathComponents: ([String], Bool)) -> ([String], Bool) {
    var (components, absolute) = pathComponents

    guard components.contains(where: { $0 == "." || $0 == ".." }) else {
      return pathComponents
    }

    if !absolute {
      guard let currentObjectPath else { return pathComponents }
      components = currentObjectPath.filter { !$0.isEmpty } + components
      absolute = true
    }

    let normalized = components.reduce(into: OcaNamePath()) { path, component in
      switch component {
      case ".":
        break
      case "..":
        if !path.isEmpty { path.removeLast() }
      default:
        path.append(component)
      }
    }

    return (normalized, absolute)
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
      let pathComponents = _normalize(path.pathComponents)
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

  /// Returns the roles of the action objects of `block`, suffixed with a path separator if the
  /// action object is itself a block.
  ///
  /// Where the block's action objects are cached the answer costs nothing. Where they are not,
  /// the device is asked for the roles beginning with what has been typed, which is a single
  /// call; only if it cannot answer that are all of the block's action objects enumerated, which
  /// costs a call for the list and another for each role.
  private func _resolveObjectCompletions(
    _ block: OcaBlock,
    path: OcaNamePath?,
    matching partialRole: String
  ) async -> [String]? {
    var completions: [String]?

    if let roles = try? await block.completeCachedActionObjectRoles, !roles.isEmpty {
      completions = roles.map { $0.1 + ($0.0 is OcaBlock ? String(ocaPathSeparator) : "") }
    } else if let found = await _findActionObjects(in: block, matching: partialRole) {
      completions = found
    } else if let actionObjects = try? await block.resolveActionObjects() {
      completions = await actionObjects.asyncCompactMap { actionObject in
        guard let role = try? await actionObject.getRole() else { return nil }
        return role + (actionObject is OcaBlock ? String(ocaPathSeparator) : "")
      }
    }

    guard var completions else { return nil }

    // the sparse role path cache may know of descendants of `block` that we did not
    // enumerate, because they were found with FindActionObjectsByPath()
    if let path {
      completions.append(contentsOf: sparseRolePathCache.keys.filter {
        $0.count > path.count && Array($0.prefix(path.count)) == path
      }.map {
        $0[path.count] + ($0.count > path.count + 1 ? String(ocaPathSeparator) : "")
      })
    }

    return Array(Swift.Set(completions)).sorted()
  }

  /// Asks the device for the roles of `block`'s action objects that begin with what has been
  /// typed, which is how completion works before any of the hierarchy has been resolved. Returns
  /// nil if the device cannot answer, so that the caller falls back to enumerating.
  ///
  /// Each role that comes back is remembered on the object it belongs to, so that asking for it
  /// again is free. Nothing else is cached: a search returns the objects that matched, which
  /// says nothing about the ones that did not, and recording that as the block's action objects
  /// would be recording a part as the whole.
  private func _findActionObjects(
    in block: OcaBlock,
    matching partialRole: String
  ) async -> [String]? {
    guard contextFlags.contains(.supportsFindActionObjectsByRole) else { return nil }

    let searchResults: [OcaObjectSearchResult]

    do {
      searchResults = try await block.find(
        actionObjectsByRole: partialRole,
        nameComparisonType: .substring,
        resultFlags: [.oNo, .role, .classIdentification]
      )
    } catch Ocp1Error.status(.notImplemented) {
      contextFlags.remove(.supportsFindActionObjectsByRole)
      return nil
    } catch {
      return nil
    }

    // A device that does not search the way this expects looks the same as one where nothing
    // matched, so let the caller enumerate rather than report a block as having no children.
    guard !searchResults.isEmpty else { return nil }

    for searchResult in searchResults {
      guard let role = searchResult.role, let oNo = searchResult.oNo,
            let classIdentification = searchResult.classIdentification,
            let object = try? await connection.resolve(object: OcaObjectIdentification(
              oNo: oNo,
              classIdentification: classIdentification
            ))
      else {
        continue
      }
      object.cacheRole(role)
    }

    return searchResults.compactMap { searchResult in
      guard let role = searchResult.role else { return nil }
      let isBlock = searchResult.classIdentification?
        .isSubclass(of: OcaBlock.classIdentification) ?? false
      return role + (isBlock ? String(ocaPathSeparator) : "")
    }
  }

  /// Returns completions for a partially typed role path, e.g. `/Foo/Ba`. The returned
  /// completions include the leading portion of `path` so that they can replace it verbatim.
  ///
  /// This may query the device: the line editor awaits it rather than blocking on it.
  func resolveCompletions(forPartialRolePath path: String) async -> [String]? {
    let container: String
    let partialRole: String

    if let separatorIndex = path.lastIndex(of: ocaPathSeparator) {
      container = String(path[...separatorIndex])
      partialRole = String(path[path.index(after: separatorIndex)...])
    } else {
      container = ""
      partialRole = path
    }

    let object: OcaRoot
    if container.isEmpty {
      object = currentObject
    } else if let containerObject: OcaRoot = try? await resolve(rolePath: container) {
      object = containerObject
    } else {
      return nil
    }

    guard let block = object as? OcaBlock else { return nil }

    let containerPath: OcaNamePath? = if container.isEmpty {
      currentObjectPath
    } else {
      try? await block.getRolePath(flags: contextFlags.cachedPropertyResolutionFlags)
    }

    guard let completions = await _resolveObjectCompletions(
      block,
      path: containerPath,
      matching: partialRole
    ) else { return nil }

    return completions.filter { $0.hasPrefix(partialRole) }.map { container + $0 }
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
  }

  var currentPathString: String {
    if let currentObjectPath {
      currentObjectPath.pathString
    } else {
      currentObject.objectNumber.oNoString
    }
  }

  /// Runs `body`, cancelling it if the user presses escape. Returns nil if it was interrupted.
  @discardableResult
  func withInterruption<T: Sendable>(
    _ body: @escaping @Sendable () async throws -> T
  ) async throws -> T? {
    guard let lineReader else { return try await body() }
    return try await lineReader.withInterruption(body)
  }

  let lock = NSRecursiveLock()

  func print(_ items: Any...) {
    lock.lock()
    defer { lock.unlock() }
    Swift.print(items, separator: " ", terminator: "\n")
  }

  @Sendable
  func onEvent(event: OcaEvent, eventData data: Data) {
    let decoder = Ocp1Decoder()
    var propertyID: OcaPropertyID?

    if event.eventID == OcaPropertyChangedEventID {
      propertyID = try? decoder.decode(OcaPropertyID.self, from: data)
    }

    Task {
      do {
        let emitter = await connection.resolve(cachedObject: event.emitterONo)
        let emitterPath: String = if let emitter {
          try await emitter
            .getRolePathString(flags: contextFlags.cachedPropertyResolutionFlags)
        } else {
          event.emitterONo.oNoString
        }
        if event.eventID == OcaPropertyChangedEventID, let propertyID {
          logger
            .info(
              "event \(event.eventID) from \(emitterPath) property \(propertyID) data \(data.hexString)"
            )
        } else {
          logger.info("event \(event.eventID) from \(emitterPath) data \(data.hexString)")
        }
      } catch {
        logger.error("Failed to process property event: \(error)")
      }
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

  static func getCompletions(with context: Context, currentBuffer: String) async -> [String]? {
    nil
  }
}
#endif
