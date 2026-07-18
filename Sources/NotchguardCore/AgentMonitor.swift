import Foundation
import Darwin

public final class AgentMonitor: @unchecked Sendable {
    private let parser: any OutputParsing
    private let notify: @Sendable (AgentEvent, AgentSession) -> Void

    public init(parser: any OutputParsing, notify: @escaping @Sendable (AgentEvent, AgentSession) -> Void) {
        self.parser = parser
        self.notify = notify
    }

    @discardableResult
    public func run(command: String, arguments: [String]) throws -> Int32 {
        let executable = try resolve(command: command)
        let session = AgentSession(
            agentName: command == "claude" ? "Claude" : "Codex",
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            terminalTTY: terminalTTY()
        )
        let process = Process()
        // `script` gives the wrapped agent a genuine pseudo-terminal. Claude Code
        // and Codex both use terminal capabilities for their interactive flows.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", executable.path] + arguments
        process.standardInput = FileHandle.standardInput

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let readerFinished = DispatchSemaphore(value: 0)
        let gate = EventGate()
        DispatchQueue.global(qos: .userInitiated).async { [parser, notify] in
            var buffered = TerminalOutputBuffer()
            while true {
                let data = output.fileHandleForReading.availableData
                guard !data.isEmpty else { break }
                FileHandle.standardOutput.write(data)
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                for line in buffered.append(chunk) {
                    if let event = parser.parse(line: line), gate.shouldDeliver(event) {
                        notify(event, session)
                    }
                }
            }
            if let line = buffered.flush(),
               let event = parser.parse(line: line),
               gate.shouldDeliver(event) {
                notify(event, session)
            }
            readerFinished.signal()
        }
        process.waitUntilExit()
        readerFinished.wait()

        let status = process.terminationStatus
        if status == 0 {
            notify(
                AgentEvent(kind: .completed, summary: "Work in \(session.projectName) is done."),
                session
            )
        } else if status != 130 {
            notify(
                AgentEvent(kind: .failed, summary: "Exited with status \(status) in \(session.projectName)."),
                session
            )
        }
        return status
    }

    private func resolve(command: String) throws -> URL {
        if command.contains("/") { return URL(fileURLWithPath: command) }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        if let found = paths.map({ URL(fileURLWithPath: String($0)).appendingPathComponent(command) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) { return found }
        throw NSError(domain: "Notchguard", code: 127, userInfo: [NSLocalizedDescriptionKey: "Could not find '\(command)' on PATH."])
    }

    private func terminalTTY() -> String? {
        guard isatty(STDIN_FILENO) != 0, let pointer = ttyname(STDIN_FILENO) else { return nil }
        return String(cString: pointer)
    }
}
