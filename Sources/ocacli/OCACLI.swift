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

import AsyncAlgorithms
import CommandLineKit
import Foundation
import Logging
import SwiftOCA

@main
final class OCACLI: Command {
    @CommandArgument(short: "h", long: "hostname", description: "Device host name")
    private var hostname: String?
    @CommandArguments(short: "c", long: "command", description: "Commands to execute")
    private var commandsToExecute: [String]
    @CommandArgument(short: "p", long: "port", description: "Device port")
    private var port: Int?
    @CommandOption(short: "U", long: "udp", description: "Use datagram sockets")
    private var udp: Bool
    @CommandOption(
        short: "r",
        long: "resolve-device-tree",
        description: "Resolve device action objects at startup"
    )
    private var resolveDeviceTree: Bool
    @CommandOption(
        short: "s",
        long: "subscribe-properties",
        description: "Subscribe to property change events"
    )
    private var cacheProperties: Bool
    @CommandArgument(short: "l", long: "log-level", description: "Log level")
    private var logLevel: String?
    @CommandOption(long: "help", description: "Show usage description")
    private var help: Bool
    @CommandFlags // Inject the flags object
    private var flags: CommandLineKit.Flags

    private let lineReader = LineReader()
    private let commands = REPLCommandRegistry.shared

    private typealias CommandTokens = [String]
    private var context: Context!
    private var commandSourceStream: AsyncStream<CommandTokens>!
    private let commandDidComplete = DispatchSemaphore(value: 0)

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
        commands.register(Watch.self)
    }

    private func usage() -> Never {
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

    private func readCommand(_ ln: LineReader, withPrompt prompt: String) throws -> String {
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

    private func initContext() async throws -> Context {
        var logger = Logger(label: "com.padl.ocacli")

        guard let hostname, let port, !help else {
            usage()
        }

        if let logLevel = logLevel {
            guard let logLevel = Logger.Level(rawValue: logLevel) else {
                usage()
            }
            logger.logLevel = logLevel
        }

        var contextFlags: ContextFlags = [
            .enableRolePathLookupCache,
            .supportsFindActionObjectsByPath,
        ]
        let deviceEndpointInfo: DeviceEndpointInfo

        if resolveDeviceTree {
            contextFlags.insert(.refreshDeviceTreeOnConnection)
        }
        if cacheProperties {
            contextFlags.insert([.cacheProperties, .subscribePropertyEvents])
        }

        guard let port = UInt16(exactly: port) else {
            throw Ocp1Error.serviceResolutionFailed
        }

        if udp {
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

    private func readCommand() throws -> [String] {
        let prompt = "\(context.currentPathString)> "
        let commandLine = try readCommand(lineReader!, withPrompt: prompt)
        return commands.tokenizeCommand(commandLine)
    }

    private func executeCommand(context: Context, tokens: [String]) async throws {
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

    private func commandSourceEventLoop(
        _ continuation: AsyncStream<CommandTokens>
            .Continuation
    ) throws {
        guard let lineReader = lineReader else { throw Ocp1Error.invalidHandle }

        lineReader.setCompletionCallback { currentBuffer in
            guard let completions = self.commands.getCompletions(
                from: currentBuffer,
                context: self.context
            ) else { return [] }
            return completions.filter { $0.hasPrefix(currentBuffer) }
        }

        var done = false
        while !done {
            do {
                commandDidComplete.wait()
                let tokens = try readCommand()
                continuation.yield(tokens)
                lineReader.addHistory(tokens.joined(separator: " "))
            } catch LineReaderError.CTRLC, LineReaderError.EOF {
                done = true
            } catch {
                context.print(error)
            }
        }
    }

    private func initCommandSourceStream() -> AsyncStream<CommandTokens>.Continuation {
        var continuation: AsyncStream<CommandTokens>.Continuation!
        commandSourceStream = AsyncStream<CommandTokens> {
            let task = Task {
                self.context = try await self.initContext()
                commandDidComplete.signal()
                for await tokens in commandSourceStream {
                    do {
                        try await executeCommand(context: context, tokens: tokens)
                    } catch {
                        context.print(error)
                    }
                    commandDidComplete.signal()
                }
            }
            $0.onTermination = { @Sendable _ in
                task.cancel()
            }
            continuation = $0
        }
        return continuation
    }

    private func runInteractiveMode() throws {
        let continuation = initCommandSourceStream()
        DispatchQueue(label: "com.padl.ocacli.repl", qos: .utility).sync {
            try? self.commandSourceEventLoop(continuation)
            continuation.yield([Exit.name[0]])
        }
    }

    private func runBatchMode(_ commandsToExecute: [String]) throws {
        let continuation = initCommandSourceStream()
        for commandToExecute in commandsToExecute + [Exit.name[0]] {
            let tokens = commands.tokenizeCommand(commandToExecute)
            continuation.yield(tokens)
        }
    }

    func run() throws {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)

        if commandsToExecute.isEmpty {
            try runInteractiveMode()
        } else {
            try runBatchMode(commandsToExecute)
        }
        dispatchMain()
    }
}
