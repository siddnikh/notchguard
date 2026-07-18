import Foundation

public protocol NotificationSending: Sendable {
    func send(_ event: AgentEvent, session: AgentSession)
}

public struct OverlayPayload: Codable, Equatable, Sendable {
    public let event: AgentEvent
    public let session: AgentSession

    public init(event: AgentEvent, session: AgentSession) {
        self.event = event
        self.session = session
    }

    public func encoded() throws -> String {
        try JSONEncoder().encode(self).base64EncodedString()
    }

    public static func decode(_ value: String) throws -> OverlayPayload {
        guard let data = Data(base64Encoded: value) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(OverlayPayload.self, from: data)
    }
}

public final class NotchNotifier: NotificationSending, @unchecked Sendable {
    public static let shared = NotchNotifier()

    public func send(_ event: AgentEvent, session: AgentSession) {
        guard let payload = try? OverlayPayload(event: event, session: session).encoded() else { return }
        let process = Process()
        process.executableURL = currentExecutable()
        process.arguments = ["__present", payload]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func currentExecutable() -> URL {
        let argument = CommandLine.arguments[0]
        if argument.contains("/") {
            return URL(
                fileURLWithPath: argument,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ).standardizedFileURL
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return paths
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(argument) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            ?? URL(fileURLWithPath: argument)
    }
}

public enum TerminalJumper {
    public static func jump(to directory: URL, terminalTTY: String? = nil) throws {
        if let terminalTTY, try activateTerminalTab(terminalTTY) { return }
        try openTerminal(at: directory)
    }

    private static func activateTerminalTab(_ terminalTTY: String) throws -> Bool {
        let script = """
        on run argv
            set targetTTY to item 1 of argv
            tell application "Terminal"
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        if tty of terminalTab is targetTTY then
                            set selected tab of terminalWindow to terminalTab
                            set index of terminalWindow to 1
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
        end run
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, terminalTTY]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let response = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && response == "found"
    }

    private static func openTerminal(at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", directory.path]
        try process.run()
    }
}
