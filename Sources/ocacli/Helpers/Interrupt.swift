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

import Foundation

/// Watches the terminal for the escape key whilst a command runs, so that a command which would
/// otherwise run forever can be abandoned without leaving the CLI. Ctrl-C is deliberately left
/// alone, and still terminates the process.
///
/// May only be used from a command, i.e. whilst the line editor is not itself reading standard
/// input, otherwise the two would compete for keystrokes.
private final class Interrupter: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.padl.ocacli.interrupt", qos: .userInteractive)
  private let readSource: (any DispatchSourceRead)?
  private let didCancelReadSource = DispatchSemaphore(value: 0)
  private var savedTermios = termios()

  init(onInterrupt: @escaping @Sendable () -> ()) {
    guard isatty(STDIN_FILENO) != 0 else {
      readSource = nil
      return
    }

    tcgetattr(STDIN_FILENO, &savedTermios)
    var raw = savedTermios
    /// disable line buffering and echo so that a keystroke is delivered immediately, but keep
    /// ISIG (so that Ctrl-C and Ctrl-Z behave as usual) and OPOST (so that the command's own
    /// output is still translated)
    raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
    withUnsafeMutablePointer(to: &raw.c_cc) {
      $0.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
        cc[Int(VMIN)] = 1
        cc[Int(VTIME)] = 0
      }
    }
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)

    let readSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
    /// the cancellation handler must be installed before the source can cancel itself below,
    /// otherwise stop() could wait for a handler that will never run
    readSource.setCancelHandler { [didCancelReadSource] in didCancelReadSource.signal() }
    /// the reference cycle between the source and its handler is broken when it is cancelled
    readSource.setEventHandler {
      var key: UInt8 = 0
      let count = read(STDIN_FILENO, &key, 1)
      guard count > 0 else {
        /// a read interrupted by a signal will be retried when the source next fires
        if count < 0, errno == EINTR { return }
        /// at end of file the source would otherwise fire continuously
        readSource.cancel()
        onInterrupt()
        return
      }
      if key == 0x1B { onInterrupt() }
    }
    readSource.resume()
    self.readSource = readSource
  }

  /// Must complete before the line editor reads again, otherwise the read source could consume
  /// the first keystroke of the next command.
  func stop() {
    guard let readSource else { return }
    readSource.cancel()
    _ = didCancelReadSource.wait(timeout: .now() + 1)
    /// TCSAFLUSH discards anything typed whilst the command was running
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
  }
}

/// Runs `body`, cancelling it if the user presses escape. Returns nil if it was interrupted.
@discardableResult
func withInterruption<T: Sendable>(
  _ body: @escaping @Sendable () async throws -> T
) async throws -> T? {
  let task = Task { try await body() }
  let interrupter = Interrupter { task.cancel() }
  defer { interrupter.stop() }

  do {
    return try await task.value
  } catch is CancellationError {
    return nil
  }
}
