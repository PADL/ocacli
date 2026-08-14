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

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
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

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

// Per-read chunk size for dump-dataset. The device may return less if it's hit
// end-of-data; we just keep looping until endOfData is true.
private let datasetReadChunkSize: OcaUint64 = 4096

private func parseDatasetSource(_ source: String) throws -> Data {
  if source.lowercased().hasPrefix("0x") {
    return try Data(fromHexEncodedString: source)
  }
  guard let url = URL(string: source), url.isFileURL else {
    throw Ocp1Error.status(.badFormat)
  }
  return try Data(contentsOf: url)
}

struct DumpDataset: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["dump-dataset"]
  static let summary = "Read dataset contents to a file URL or base64 stdout"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaDataset.classIdentification]
  }

  var minimumRequiredArguments: Int { 0 }

  @REPLCommandArgument
  var destination: String!

  init() {}

  func execute(with context: Context) async throws {
    let dataset = context.currentObject as! OcaDataset
    let (size, handle) = try await dataset.openRead(lockState: .noLock)

    var buffer = Data()
    buffer.reserveCapacity(Int(size))
    var position: OcaUint64 = 0
    do {
      while true {
        let (endOfData, part) = try await dataset.read(
          handle: handle,
          position: position,
          partSize: datasetReadChunkSize
        )
        buffer.append(part.wrappedValue)
        position += OcaUint64(part.wrappedValue.count)
        if endOfData { break }
        if part.wrappedValue.isEmpty { break }
      }
      try await dataset.close(handle: handle)
    } catch {
      try? await dataset.close(handle: handle)
      throw error
    }

    if let destination, destination != "-" {
      guard let url = URL(string: destination), url.isFileURL else {
        throw Ocp1Error.status(.badFormat)
      }
      try buffer.write(to: url)
    } else {
      context.print(buffer.base64EncodedString())
    }
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct LoadDataset: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["load-dataset"]
  static let summary = "Write dataset contents from a file URL or 0x-prefixed hex blob"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaDataset.classIdentification]
  }

  @REPLCommandArgument
  var source: String!

  init() {}

  func execute(with context: Context) async throws {
    let dataset = context.currentObject as! OcaDataset
    let payload = try parseDatasetSource(source)
    let (maxPartSize, handle) = try await dataset.openWrite(lockState: .noLock)
    let chunkSize = maxPartSize == 0 ? OcaUint64(payload.count) : maxPartSize

    do {
      var position = 0
      while position < payload.count {
        let end = min(position + Int(chunkSize), payload.count)
        let chunk = payload[position..<end]
        try await dataset.write(
          handle: handle,
          position: OcaUint64(position),
          part: OcaLongBlob(chunk)
        )
        position = end
      }
      try await dataset.close(handle: handle)
    } catch {
      try? await dataset.close(handle: handle)
      throw error
    }
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct ClearDataset: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["clear-dataset"]
  static let summary = "Clear dataset contents"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaDataset.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let dataset = context.currentObject as! OcaDataset
    let (_, handle) = try await dataset.openWrite(lockState: .noLock)
    do {
      try await dataset.clear(handle: handle)
      try await dataset.close(handle: handle)
    } catch {
      try? await dataset.close(handle: handle)
      throw error
    }
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct GetDatasetSizes: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["get-dataset-sizes"]
  static let summary = "Get current and maximum dataset size in bytes"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaDataset.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let dataset = context.currentObject as! OcaDataset
    let (current, max) = try await dataset.getDataSetSizes()
    context.print("current: \(current) max: \(max)")
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct ConstructDataset: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["construct-dataset"]
  static let summary = "Construct a dataset (classID name mimeType maxSize [initialContents])"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  var minimumRequiredArguments: Int { 4 }

  @REPLCommandArgument
  var classID: String!

  @REPLCommandArgument
  var name: String!

  @REPLCommandArgument
  var type: String!

  @REPLCommandArgument
  var maxSize: UInt!

  @REPLCommandArgument
  var initialContents: String!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    let initial: Data = if let initialContents {
      try parseDatasetSource(initialContents)
    } else {
      Data()
    }
    let oNo = try await block.constructDataset(
      classID: OcaClassID(unsafeString: classID),
      name: name,
      type: type,
      maxSize: OcaUint64(maxSize),
      initialContents: OcaLongBlob(initial)
    )
    context.print(oNo.oNoString)
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct DuplicateDataset: REPLCommand, REPLCurrentBlockCompletable, REPLClassSpecificCommand {
  static let name = ["duplicate-dataset"]
  static let summary = "Duplicate a dataset into a target block (oldONo targetBlock newName newMaxSize)"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  @REPLCommandArgument
  var oldONo: OcaONo!

  @REPLCommandArgument
  var targetBlock: OcaRoot!

  @REPLCommandArgument
  var newName: String!

  @REPLCommandArgument
  var newMaxSize: UInt!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    let oNo = try await block.duplicateDataset(
      oldONo: oldONo,
      targetBlockONo: targetBlock.objectNumber,
      newName: newName,
      newMaxSize: OcaUint64(newMaxSize)
    )
    context.print(oNo.oNoString)
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct GetDatasetObjectsRecursive: REPLCommand, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["get-dataset-objects-recursive"]
  static let summary = "Recursively list dataset objects under this block"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    let members = try await block.getDatasetObjectsRecursive()
    for member in members {
      context.print(member.memberObjectIdentification.oNo.oNoString)
    }
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

private func printDatasetSearchResults(
  _ results: [OcaDatasetSearchResult],
  context: Context
) {
  for r in results {
    context.print(
      "\(r.object.memberObjectIdentification.oNo.oNoString)\t\(r.type)\t\(r.name)"
    )
  }
}

struct FindDatasets: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["find-datasets"]
  static let summary = "Find datasets by name (name [type])"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var name: String!

  @REPLCommandArgument
  var type: String!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    let results = try await block.findDatasets(
      name: name,
      nameComparisonType: .containsCaseInsensitive,
      type: type ?? "",
      typeComparisonType: .containsCaseInsensitive
    )
    printDatasetSearchResults(results, context: context)
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}

struct FindDatasetsRecursive: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable,
  REPLClassSpecificCommand
{
  static let name = ["find-datasets-recursive"]
  static let summary = "Recursively find datasets by name (name [type])"

  static var supportedClasses: [OcaClassIdentification] {
    [OcaBlock.classIdentification]
  }

  var minimumRequiredArguments: Int { 1 }

  @REPLCommandArgument
  var name: String!

  @REPLCommandArgument
  var type: String!

  init() {}

  func execute(with context: Context) async throws {
    let block = context.currentObject as! OcaBlock
    let results = try await block.findDatasetsRecursive(
      name: name,
      nameComparisonType: .containsCaseInsensitive,
      type: type ?? "",
      typeComparisonType: .containsCaseInsensitive
    )
    printDatasetSearchResults(results, context: context)
  }

  static func getCompletions(with context: Context, buffer: String) async -> [String]? { nil }
}
