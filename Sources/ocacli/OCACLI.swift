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

@main
final class OCACLI: Command {
    @CommandArgument(short: "h", long: "hostname", description: "Device host name")
    var hostname: String?
    @CommandArgument(short: "p", long: "port", description: "Device port")
    var port: Int?
    @CommandOption(short: "U", long: "udp", description: "Use datagram sockets")
    var udp: Bool
    @CommandOption(
        short: "r",
        long: "resolve-device-tree",
        description: "Resolve device action objects at startup"
    )
    var resolveDeviceTree: Bool
    @CommandOption(
        short: "c",
        long: "cache-properties",
        description: "Cache property values and subscribe to change events"
    )
    var cacheProperties: Bool
    @CommandOption(long: "help", description: "Show usage description")
    var help: Bool
    @CommandFlags // Inject the flags object
    var flags: CommandLineKit.Flags

    let lineReader = LineReader()
    let commands = REPLCommandRegistry.shared

    init() {
        commands.register(ChangePath.self)
        commands.register(ClearCache.self)
        commands.register(ClearFlag.self)
        commands.register(Connect.self)
        commands.register(ConnectionInfo.self)
        commands.register(DeviceInfo.self)
        commands.register(Disconnect.self)
        commands.register(Dump.self)
        commands.register(Exit.self)
        commands.register(Flags.self)
        commands.register(Get.self)
        commands.register(List.self)
        commands.register(PrintWorkingPath.self)
        commands.register(Resolve.self)
        commands.register(SetFlag.self)
        commands.register(Set.self)
        commands.register(Show.self)
        commands.register(Subscribe.self)
        commands.register(Up.self)
        commands.register(Unsubscribe.self)
    }

    func readCommand(_ ln: LineReader, withPrompt prompt: String) throws -> String {
        let commandLine = try ln.readLine(
            prompt: prompt,
            maxCount: 200,
            strippingNewline: true,
            promptProperties: TextProperties(.green, nil, .bold),
            readProperties: TextProperties(.blue, nil),
            parenProperties: TextProperties(.red, nil, .bold)
        )
        return commandLine
    }

    func run() throws {
        guard let hostname, let port, !help else {
            print(
                flags.usageDescription(
                    usageName: TextStyle.bold.properties.apply(to: "usage:"),
                    synopsis: "[<option> ...] [---] [<program> <arg> ...]",
                    usageStyle: TextProperties.none,
                    optionsName: TextStyle.bold.properties.apply(to: "options:"),
                    flagStyle: TextStyle.italic.properties
                ),
                terminator: ""
            )
            exit(0)
        }

        let queue = DispatchQueue(label: "com.padl.ocacli.repl", qos: .utility)
        try queue.sync {
            guard let lineReader = self.lineReader else { throw Ocp1Error.invalidHandle }
            let context: Context

            context = try Task.synchronous {
                var contextFlags: ContextFlags = [
                    .enableRolePathLookupCache,
                    .supportsFindActionObjectsByPath,
                ]
                let deviceEndpointInfo: DeviceEndpointInfo

                if self.resolveDeviceTree {
                    contextFlags.insert(.refreshDeviceTreeOnConnection)
                }
                if self.cacheProperties {
                    contextFlags.insert([.cacheProperties, .subscribePropertyEvents])
                }

                guard let port = UInt16(exactly: port) else {
                    throw Ocp1Error.serviceResolutionFailed
                }

                if self.udp {
                    deviceEndpointInfo = DeviceEndpointInfo.udp(hostname, port)
                } else {
                    deviceEndpointInfo = DeviceEndpointInfo.tcp(hostname, port)
                }
                return try await Context(
                    deviceEndpointInfo: deviceEndpointInfo,
                    contextFlags: contextFlags
                )
            }

            lineReader.setCompletionCallback { currentBuffer in
                guard let completions = self.commands.getCompletions(
                    from: currentBuffer,
                    context: context
                ) else { return [] }
                return completions.filter { $0.hasPrefix(currentBuffer) }
            }

            var done = false

            while !done {
                do {
                    let commandLine = try self.readCommand(
                        lineReader,
                        withPrompt: "\(context.currentPathString)> "
                    )
                    let tokens = self.commands.tokenizeCommand(commandLine)
                    if tokens.count == 0 {
                        continue
                    }

                    try Task.synchronous {
                        let command = try await self.commands.command(
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
                    lineReader.addHistory(commandLine)
                } catch LineReaderError.CTRLC, LineReaderError.EOF {
                    try Task.synchronous { await context.finish() }
                    done = true
                } catch {
                    context.print(error)
                }
            }
        }
    }
}
