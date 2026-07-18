import Foundation

public final class AgentMonitor: @unchecked Sendable {
    private let parser: any OutputParsing
    private let notify: @Sendable (AgentEvent) -> Void

    public init(parser: any OutputParsing, notify: @escaping @Sendable (AgentEvent) -> Void) {
        self.parser = parser
        self.notify = notify
    }

    @discardableResult
    public func run(command: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        // `script` gives the wrapped agent a genuine pseudo-terminal. Claude Code
        // and Codex both use terminal capabilities for their interactive flows.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", try resolve(command: command).path] + arguments
        process.standardInput = FileHandle.standardInput

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let lock = NSLock()
        var buffered = ""
        output.fileHandleForReading.readabilityHandler = { [parser, notify] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            FileHandle.standardOutput.write(data)
            lock.lock()
            buffered += chunk
            let lines = buffered.components(separatedBy: .newlines)
            buffered = lines.last ?? ""
            lock.unlock()
            for line in lines.dropLast() {
                if let event = parser.parse(line: line) { notify(event) }
            }
        }
        try process.run()
        // Keep the main run loop alive so a notch overlay can respond while the
        // command is running, without taking focus away from the terminal.
        while process.isRunning {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        output.fileHandleForReading.readabilityHandler = nil
        return process.terminationStatus
    }

    private func resolve(command: String) throws -> URL {
        if command.contains("/") { return URL(fileURLWithPath: command) }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        if let found = paths.map({ URL(fileURLWithPath: String($0)).appendingPathComponent(command) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) { return found }
        throw NSError(domain: "Notchguard", code: 127, userInfo: [NSLocalizedDescriptionKey: "Could not find '\(command)' on PATH."])
    }
}
