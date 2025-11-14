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

import Foundation
import SwiftOCA

struct ApplyParamDataSet: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["apply-param-data-set"]
  static let summary = "Apply parameter data set"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  @REPLCommandArgument
  var paramDataset: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    try await block.apply(paramDataset: paramDataset)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct StoreCurrentParamData: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["store-current-param-data"]
  static let summary = "Store current parameter data"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  @REPLCommandArgument
  var currentParameterData: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    try await block.store(currentParameterData: currentParameterData)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct FetchCurrentParameterData: REPLCommand, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["fetch-current-param-data"]
  static let summary = "Fetch current parameter data"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    let paramData = try await block.fetchCurrentParameterData()
    print("0x\(Data(paramData).hexString))")
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ApplyParameterData: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["apply-param-data"]
  static let summary = "Apply hex-encoded parameter data blob"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  @REPLCommandArgument
  var parameterData: OcaString!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    guard let parameterData = Data(hex: parameterData) else { throw Ocp1Error.status(.badFormat) }
    try await block.apply(parameterData: OcaLongBlob(parameterData))
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}

struct ApplyPatch: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["apply-patch"]
  static let summary = "Apply parameter data set"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaDeviceManager.classIdentification]
  }

  @REPLCommandArgument
  var datasetONo: OcaONo!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaDeviceManager
    try await block.applyPatch(datasetONo: datasetONo)
  }

  static func getCompletions(with context: Context, currentBuffer: String) -> [String]? { nil }
}
