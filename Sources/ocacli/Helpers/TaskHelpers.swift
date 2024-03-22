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

class Box<Success: Sendable, Failure: Error>: @unchecked
Sendable {
    var result: Result<Success, Error>!
    let semaphore = DispatchSemaphore(value: 0)

    func blockingWait(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success
    ) throws -> Success {
        Task<(), Never>(priority: priority) {
            defer { semaphore.signal() }

            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
        }

        semaphore.wait()
        return try result.get()
    }
}

extension Task where Failure == Error {
    /// Performs an async task in a sync context.
    ///
    /// - Note: This function blocks the thread until the given operation is finished. The caller is
    /// responsible for managing multithreading.
    static func synchronous(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success
    ) throws -> Success {
        let box = Box<Success, Failure>()
        return try box.blockingWait(priority: priority, operation: operation)
    }
}
