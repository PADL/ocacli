//
// Copyright (c) 2026 PADL Software Pty Ltd
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

@testable import ocacli
import SwiftOCA
import XCTest

final class CM4ArgumentTests: XCTestCase {
  private static let sdp = "v=0\r\ns=pair\r\n"

  private func assertUsageError(
    _ body: () throws -> some Any,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try body(), file: file, line: line) {
      XCTAssertTrue($0 is REPLCommandRegistry.UsageError, "\($0)", file: file, line: line)
    }
  }

  func testStartIsTrueOrFalseOnly() throws {
    XCTAssertTrue(try ConnectEndpoint.parseStart(nil))
    XCTAssertTrue(try ConnectEndpoint.parseStart("true"))
    XCTAssertFalse(try ConnectEndpoint.parseStart("false"))
    // NSString.boolValue would read these as false
    for argument in ["start", "on", "yes", "1", "TRUE", ""] {
      assertUsageError { try ConnectEndpoint.parseStart(argument) }
    }
  }

  func testMediaIDArgumentsNameAnAes67MediaIDType() throws {
    XCTAssertNil(try ConnectEndpoint.parseMediaID(type: nil, id: nil, remote: Self.sdp))
    XCTAssertNil(try ConnectEndpoint.parseMediaID(type: nil, id: nil, remote: "stage left"))
    let mid = try XCTUnwrap(ConnectEndpoint.parseMediaID(type: "mid", id: "aux", remote: Self.sdp))
    XCTAssertEqual(mid.0, .mid)
    XCTAssertEqual(mid.1, "aux")
    for type in Aes67MediaIDType.allCases {
      let parsed = try ConnectEndpoint.parseMediaID(type: "\(type)", id: "1", remote: Self.sdp)
      XCTAssertEqual(parsed?.0, type)
    }
    assertUsageError { try ConnectEndpoint.parseMediaID(type: "port", id: "5004", remote: Self.sdp) }
    assertUsageError { try ConnectEndpoint.parseMediaID(type: "3", id: "aux", remote: Self.sdp) }
    // both or neither
    assertUsageError { try ConnectEndpoint.parseMediaID(type: "mid", id: nil, remote: Self.sdp) }
    // a registry entry names its stream itself
    assertUsageError { try ConnectEndpoint.parseMediaID(type: "mid", id: "aux", remote: "stage left") }
  }

  func testAFailedStartSaysTheConfigureSucceeded() {
    let failed = ConnectEndpoint.StartFailed(endpointID: 3, underlying: Ocp1Error.status(.invalidRequest))
    XCTAssertEqual("\(failed)", "endpoint 3 configured, Ready; start failed: invalidRequest")
  }

  func testEndpointCommandsAreNamedAsSwiftOCANamesThem() throws {
    XCTAssertEqual(
      ApplyEndpointCommand.commandNames,
      ["none", "setReady", "connect", "connectAndStart", "disconnect", "stopAndDisconnect", "start", "stop"]
    )
    for (name, command) in zip(ApplyEndpointCommand.commandNames, OcaMediaStreamEndpointCommand.allCases) {
      XCTAssertEqual(try ApplyEndpointCommand.parseCommand(name), command)
    }
    for name in ["ConnectAndStart", "connect-and-start", "3", "go"] {
      assertUsageError { try ApplyEndpointCommand.parseCommand(name) }
    }
  }
}
