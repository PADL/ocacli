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
    @CommandArguments(short: "c", long: "command", description: "Commands to execute")
    var commandsToExecute: [String]
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
        short: "s",
        long: "subscribe-properties",
        description: "Subscribe to property change events"
    )
    var cacheProperties: Bool
    @CommandArgument(short: "l", long: "log-level", description: "Log level")
    var logLevel: String?
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
        commands.register(Monitor.self)
        commands.register(PrintWorkingPath.self)
        commands.register(PushPath.self)
        commands.register(PopPath.self)
        commands.register(Resolve.self)
        commands.register(SetFlag.self)
        commands.register(Set.self)
        commands.register(Show.self)
        commands.register(Statistics.self)
        commands.register(Subscribe.self)
        commands.register(Up.self)
        commands.register(Unsubscribe.self)
    }

    func usage() -> Never {
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
        exit(1)
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

    private func start() throws {
        guard let lineReader = lineReader else { throw Ocp1Error.invalidHandle }
        let context: Context

        LoggingSystem.bootstrap(StreamLogHandler.standardError)

        guard let hostname, let port, !help else {
            usage()
        }

        do {
            context = try Task.synchronous {
                var logger = Logger(label: "com.padl.ocacli")

                if let logLevel = self.logLevel {
                    guard let logLevel = Logger.Level(rawValue: logLevel) else {
                        self.usage()
                    }
                    logger.logLevel = logLevel
                }

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
                    contextFlags: contextFlags,
                    logger: logger
                )
            }
        } catch {
            print(error)
            exit(2)
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
                if !commandsToExecute.isEmpty {
                    try Task.synchronous { [self] in
                        for commandToExecute in commandsToExecute {
                            let tokens = commands.tokenizeCommand(commandToExecute)
                            let command = try await self.commands.command(
                                from: tokens,
                                context: context
                            )
                            try await command.execute(with: context)
                        }
                    }
                    done = true
                } else {
                    let commandLine = try readCommand(
                        lineReader,
                        withPrompt: "\(context.currentPathString)> "
                    )
                    let tokens = commands.tokenizeCommand(commandLine)
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
                }
            } catch LineReaderError.CTRLC, LineReaderError.EOF {
                done = true
            } catch {
                context.print(error)
                if !commandsToExecute.isEmpty { break }
            }
            try Task.synchronous { await context.finish() }
        }
    }

    func run() throws {
        let queue = DispatchQueue(label: "com.padl.ocacli.repl", qos: .utility)
        try queue.sync { try start() }
    }
}
