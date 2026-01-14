//
// Copyright (c) 2025 PADL Software Pty Ltd
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

import Algorithms
import AsyncAlgorithms
import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OcaFirmwareImageContainer
import SwiftOCA

actor FirmwareManagerHelper {
  enum VerifyImageMethod {
    case none
    case implicit
    case data(Data)
    case url(URL) // URL
    case sha256Digest
    case sha384Digest
    case sha512Digest

    init?(string: String?) {
      guard let string else {
        self = .none
        return
      }
      switch string {
      case "implicit":
        self = .implicit
      case "sha256":
        self = .sha256Digest
      case "sha384":
        self = .sha384Digest
      case "sha512":
        self = .sha512Digest
      default:
        if let data = Data(hex: string) {
          self = .data(data)
        } else if let url = URL(string: string) {
          self = .url(url)
        } else {
          return nil
        }
      }
    }
  }

  private let component: OcaComponent
  private let url: URL
  private let method: VerifyImageMethod
  private var hashFunction: (any HashFunction)?
  private let chunkSize: Int

  init(component: OcaComponent, url: URL, method: String?, chunkSize: Int) async throws {
    guard let method = VerifyImageMethod(string: method) else {
      throw Ocp1Error.status(.parameterError)
    }
    try await self.init(component: component, url: url, method: method, chunkSize: chunkSize)
  }

  init(
    component: OcaComponent,
    url: URL,
    method: VerifyImageMethod,
    chunkSize: Int
  ) async throws {
    self.component = component
    self.url = url
    self.method = method
    self.chunkSize = chunkSize

    switch self.method {
    case .sha256Digest:
      hashFunction = SHA256()
    case .sha384Digest:
      hashFunction = SHA384()
    case .sha512Digest:
      hashFunction = SHA512()
    default:
      break
    }
  }

  func process(_ body: (_: [UInt8]) async throws -> ()) async throws {
    func processData(_ data: Data) async throws {
      for chunk in Array(data).chunks(ofCount: chunkSize) {
        try await body(Array(chunk))
        hashFunction?.update(data: chunk)
      }
    }

    if url.isFileURL {
      let data = try Data(contentsOf: url)
      try await processData(data)
    } else {
      #if canImport(FoundationNetworking)
      let (data, _) = try await URLSession.shared.data(from: url)
      try await processData(data)
      #else
      let (bytes, _) = try await URLSession.shared.bytes(from: url)
      for try await chunk in bytes.chunks(ofCount: chunkSize) {
        try await body(chunk)
        hashFunction?.update(data: chunk)
      }
      #endif
    }
  }

  var verifyData: Data? {
    get async throws {
      switch method {
      case .none:
        return nil
      case .implicit:
        return Data()
      case let .data(data):
        return data
      case let .url(url):
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
      case .sha256Digest:
        fallthrough
      case .sha384Digest:
        fallthrough
      case .sha512Digest:
        return Data(hashFunction!.finalize())
      }
    }
  }
}

struct StartUpdateProcess: REPLCommand, REPLClassSpecificCommand {
  static let name = ["start-update-process"]
  static let summary = "Start firmware update process"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaFirmwareManager.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let firmwareManager = context.currentObject as! OcaFirmwareManager
    try await firmwareManager.startUpdateProcess()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

private func _parseAsyncCommandLineOption(_ async: String?) throws -> Bool {
  switch async {
  case "async":
    true
  case "sync":
    fallthrough
  case nil:
    false
  default:
    throw Ocp1Error.status(.parameterOutOfRange)
  }
}

struct BeginActiveComponentUpdate: REPLCommand, REPLClassSpecificCommand, REPLOptionalArguments {
  static let name = ["begin-active-component-update", "update-component"]
  static let summary = "Update a firmware component"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaFirmwareManager.classIdentification]
  }

  var minimumRequiredArguments: Int { 2 }

  @REPLCommandArgument
  var component: UInt!

  @REPLCommandArgument
  var url: URL!

  @REPLCommandArgument
  var verifyMethod: String?

  @REPLCommandArgument
  var async: String?

  init() {}

  func execute(with context: Context) async throws {
    guard let component, let component = UInt16(exactly: component) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }

    let async = try _parseAsyncCommandLineOption(async)
    let helper = try await FirmwareManagerHelper(
      component: component,
      url: url,
      method: verifyMethod,
      chunkSize: context.chunkSize
    )
    let firmwareManager = context.currentObject as! OcaFirmwareManager

    try await firmwareManager.beginActiveImageUpdate(component: component)

    var sequenceNumber: OcaUint32 = 1
    try await helper.process { chunk in
      try await firmwareManager.addImageData(id: sequenceNumber, OcaBlob(chunk), sync: !async)
      sequenceNumber += 1
    }

    if let verifyData = try await helper.verifyData {
      try await firmwareManager.verifyImage(OcaBlob(verifyData))
    }

    try await firmwareManager.endActiveImageUpdate()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct BeginPassiveComponentUpdate: REPLCommand, REPLClassSpecificCommand, REPLOptionalArguments {
  static let name = ["begin-passive-component-update"]
  static let summary = "Update a firmware component from a remote server"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaFirmwareManager.classIdentification]
  }

  var minimumRequiredArguments: Int { 3 }

  @REPLCommandArgument
  var component: UInt!

  @REPLCommandArgument
  var serverAddress: String!

  @REPLCommandArgument
  var updateFileName: String!

  init() {}

  func execute(with context: Context) async throws {
    guard let component = UInt16(exactly: component) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }

    let firmwareManager = context.currentObject as! OcaFirmwareManager
    let serverPort = serverAddress.split(separator: ":", maxSplits: 2)
    let serverAddress: Ocp1NetworkAddress
    let port: UInt16

    if serverPort.count > 1 {
      guard let _port = UInt16(serverPort[1]) else {
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      port = _port
    } else {
      port = 0
    }

    serverAddress = Ocp1NetworkAddress(address: String(serverPort[0]), port: port)

    try await firmwareManager.beginPassiveComponentUpdate(
      component: component,
      serverAddress: serverAddress
        .networkAddress,
      updateFileName: updateFileName
    )
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct EndUpdateProcess: REPLCommand, REPLClassSpecificCommand {
  static let name = ["end-update-process"]
  static let summary = "End firmware update process"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaFirmwareManager.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let firmwareManager = context.currentObject as! OcaFirmwareManager
    try await firmwareManager.endUpdateProcess()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct FirmwareImageContainerUpdate: REPLCommand, REPLClassSpecificCommand, REPLOptionalArguments {
  static let name = ["update-firmware-container"]
  static let summary = "Update firmware from container file"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaFirmwareManager.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var url: URL!

  @REPLCommandArgument
  var component: UInt?

  @REPLCommandArgument
  var async: String?

  init() {}

  func execute(with context: Context) async throws {
    let async = try _parseAsyncCommandLineOption(async)
    let firmwareManager = context.currentObject as! OcaFirmwareManager
    let reader = try await OcaFirmwareImageContainerURLReader.decode(url: url)

    let deviceManager = await context.connection.deviceManager
    let canApplyFirmwareUpdate = try await deviceManager.$modelGUID.getValue(
      deviceManager,
      flags: context.contextFlags.propertyResolutionFlags
    ) { modelGUID in
      reader.header.models.contains(modelGUID)
    }
    guard canApplyFirmwareUpdate else { throw Ocp1Error.status(.deviceError) }
    try await firmwareManager.startUpdateProcess()

    try await reader.withComponents { componentDescriptor, image, verifyData in
      guard !componentDescriptor.flags.contains(.local) else { return }
      if let component, let component = OcaComponent(exactly: component),
         componentDescriptor.component != component { return }

      try await firmwareManager.beginActiveImageUpdate(component: componentDescriptor.component)

      var sequenceNumber: OcaUint32 = 1
      let chunkSize = await context.chunkSize
      for chunk in Array(image).chunks(ofCount: chunkSize) {
        try await firmwareManager.addImageData(id: sequenceNumber, OcaBlob(chunk), sync: !async)
        sequenceNumber += 1
      }

      try await firmwareManager.verifyImage(OcaBlob(verifyData))
      try await firmwareManager.endActiveImageUpdate()
    }

    try await firmwareManager.endUpdateProcess()
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

extension Context {
  var chunkSize: Int {
    get async {
      await isDatagram ? 1024 : 65535
    }
  }
}
