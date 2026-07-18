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
    private let lock = NSLock()

    public func send(_ event: AgentEvent, session: AgentSession) {
        guard let payload = try? OverlayPayload(event: event, session: session).encoded() else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            let application = try presenterApplication()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", "-g", application.path, "--args", "__present", payload]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            sendFallback(event, session: session)
        }
    }

    private func presenterApplication() throws -> URL {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchguard", isDirectory: true)
        let application = support.appendingPathComponent("Notchguard Presenter.app", isDirectory: true)
        let contents = application.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let presenter = macOS.appendingPathComponent("notchguard-presenter")
        let plist = contents.appendingPathComponent("Info.plist")
        let executable = currentExecutable()

        let isCurrent = fileManager.fileExists(atPath: presenter.path)
            && fileManager.fileExists(atPath: plist.path)
            && fileManager.contentsEqual(atPath: executable.path, andPath: presenter.path)
        guard !isCurrent else { return application }

        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: presenter.path) {
            try fileManager.removeItem(at: presenter)
        }
        try fileManager.copyItem(at: executable, to: presenter)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: presenter.path)

        let properties: [String: Any] = [
            "CFBundleDisplayName": "Notchguard",
            "CFBundleExecutable": "notchguard-presenter",
            "CFBundleIdentifier": "io.notchguard.presenter",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Notchguard",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": BuildInfo.version,
            "CFBundleVersion": BuildInfo.version,
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: properties,
            format: .xml,
            options: 0
        )
        try data.write(to: plist, options: .atomic)
        try sign(application)
        return application
    }

    private func sign(_ application: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", application.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableNotLoadable)
        }
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

    private func sendFallback(_ event: AgentEvent, session: AgentSession) {
        let script = """
        on run argv
            display notification (item 2 of argv) with title (item 1 of argv)
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            script,
            "\(session.agentName) \(event.actionTitle)",
            event.summary
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
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
