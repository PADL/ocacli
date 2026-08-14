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

import AsyncLineReader
import Foundation
import SwiftOCA

/// Runs commands against a connected device, either read from the keyboard or taken from the
/// command line.
final class Session {
  private let context: Context
  private let commands = REPLCommandRegistry.shared
  private let lineReader = AsyncLineReader.LineReader()

  private static var savedTermios: termios = {
    var term = termios()
    tcgetattr(STDIN_FILENO, &term)
    return term
  }()

  /// The prompt, the line being typed, and a bracket under the cursor.
  private static let style = Style.attributes(
    prompt: TextAttributes(.green, bold: true),
    input: TextAttributes(.blue),
    matchingBracket: TextAttributes(.red, bold: true)
  )

  init(context: Context) {
    self.context = context
    _ = Self.savedTermios
    monitorConnectionState()
  }

  /// Reads and executes commands until the user exits. Completions and commands are awaited on
  /// the same task as the reader, so a command can take as long as it likes without a thread
  /// being parked on its behalf.
  func runInteractively() async {
    // commands may be interrupted from the keyboard only when there is a keyboard to read
    context.lineReader = lineReader
    await prepareLineReader()

    while true {
      let line: String
      do {
        line = try await lineReader.readLine(prompt: "\(context.currentPathString)> ")
      } catch {
        // Ctrl-C or end of input
        return
      }

      let tokens = commands.tokenizeCommand(line)
      guard !tokens.isEmpty else { continue }

      do {
        try await executeCommand(tokens: tokens)
      } catch {
        context.print(error)
      }
    }
  }

  /// Executes the commands given on the command line, stopping at the first that fails.
  func run(_ commandsToExecute: [String]) async {
    for commandToExecute in commandsToExecute {
      let tokens = commands.tokenizeCommand(commandToExecute)
      guard !tokens.isEmpty else { continue }

      do {
        try await executeCommand(tokens: tokens)
      } catch {
        context.print(error)
        return
      }
    }
  }

  func finish() async {
    try? await Exit().execute(with: context)
  }

  private func prepareLineReader() async {
    await lineReader.setStyle(Self.style)
    await lineReader.setMaximumLineLength(200)
    await lineReader.setCompletionHandler { [commands, context] line, cursor in
      await commands.getCompletions(from: line, cursor: cursor, context: context)
    }
  }

  private func executeCommand(tokens: [String]) async throws {
    guard tokens.count > 0 else { return }
    let command = try await commands.command(
      from: tokens,
      context: context
    )
    if await context.connection.isConnected == false && command
      .isUsableWhenDisconnected == false
    {
      throw Ocp1Error.notConnected
    }
    try await command.execute(with: context)
  }

  private func monitorConnectionState() {
    guard !context.contextFlags.contains(.automaticReconnect) else { return }
    let context = context
    Task {
      for try await connectionState in await context.connection.connectionState {
        if connectionState == .connectionTimedOut ||
          connectionState == .connectionFailed
        {
          Self.resetTerminal()
          context.print(Ocp1Error.notConnected)
          exit(2)
        }
      }
    }
  }

  private static func resetTerminal() {
    var term = savedTermios
    tcsetattr(STDIN_FILENO, TCSADRAIN, &term)
  }
}
