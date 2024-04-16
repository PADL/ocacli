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

struct Subscribe: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["subscribe"]
    static let summary = "Add a property event subscription"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        guard context.subscriptions[object.objectNumber] == nil
        else { throw Ocp1Error.alreadySubscribedToEvent }
        let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
        let cancellable = try await context.connection.addSubscription(
            event: event,
            callback: context.onPropertyEvent
        )
        context.subscriptions[object.objectNumber] = cancellable
    }
}

struct Unsubscribe: REPLCommand, REPLOptionalArguments, REPLCurrentBlockCompletable {
    static let name = ["unsubscribe"]
    static let summary = "Remove a property event subscription"

    var minimumRequiredArguments: Int { 0 }

    @REPLCommandArgument
    var object: OcaRoot!

    init() {}

    func execute(with context: Context) async throws {
        let object = object ?? context.currentObject
        guard let cancellable = context.subscriptions[object.objectNumber]
        else { throw Ocp1Error.notSubscribedToEvent }
        try await context.connection.removeSubscription(cancellable)
    }
}

struct Watch: REPLCommand {
    static let name = ["watch"]
    static let summary = "Monitor property events"

    @REPLCommandArgument
    var propertyName: String!

    init() {}

    func execute(with context: Context) async throws {
        guard let keyPath = context.currentObject.propertyKeyPath(for: propertyName) else {
            throw Ocp1Error.status(.parameterError)
        }

        let subject = context
            .currentObject[keyPath: keyPath] as! any OcaPropertyRepresentable

        await subject.subscribe(context.currentObject)

        for try await result in subject.async {
            switch result {
            case let .success(value):
                let string = await "\r" +
                    replString(for: value, context: context, object: context.currentObject)
                fputs(string, stdout)
                fflush(stdout)
            case let .failure(error):
                throw error
            }
        }
    }

    static func getCompletions(with context: Context, currentBuffer: String) -> [String]? {
        context.currentObject.allPropertyKeyPaths.map(\.key)
    }
}
