import Foundation

public enum BuildInfo {
    public static let version = "0.2.0"
}

public enum AgentEventKind: String, Codable, CaseIterable, Sendable {
    case inputRequired = "input_required"
    case approvalRequired = "approval_required"
    case completed
    case failed
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public let kind: AgentEventKind
    public let summary: String

    public init(kind: AgentEventKind, summary: String) {
        self.kind = kind
        self.summary = summary
    }

    public var actionTitle: String {
        switch kind {
        case .inputRequired: return "is waiting"
        case .approvalRequired: return "needs approval"
        case .completed: return "finished"
        case .failed: return "stopped"
        }
    }
}

public struct AgentSession: Codable, Equatable, Sendable {
    public let agentName: String
    public let workingDirectory: URL
    public let terminalTTY: String?

    public init(agentName: String, workingDirectory: URL, terminalTTY: String?) {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
        self.terminalTTY = terminalTTY
    }

    public var projectName: String {
        workingDirectory.lastPathComponent.isEmpty ? workingDirectory.path : workingDirectory.lastPathComponent
    }
}

public protocol OutputParsing: Sendable {
    func parse(line: String) -> AgentEvent?
}

public enum TerminalText {
    private static let escapeExpression = try! NSRegularExpression(
        pattern: #"\u001B(?:\][^\u0007]*(?:\u0007|\u001B\\)|\[[0-?]*[ -/]*[@-~])"#,
        options: []
    )

    public static func clean(_ input: String) -> String {
        let range = NSRange(input.startIndex..., in: input)
        let withoutEscapes = escapeExpression.stringByReplacingMatches(in: input, range: range, withTemplate: "")
        var characters: [Character] = []
        for character in withoutEscapes {
            if character == "\u{8}" || character == "\u{7F}" {
                if !characters.isEmpty { characters.removeLast() }
            } else if character.isASCIIControl {
                if character == "\t" { characters.append(" ") }
            } else {
                characters.append(character)
            }
        }
        return String(characters)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.allSatisfy { $0.value < 32 || $0.value == 127 }
    }
}

public struct BuiltInOutputParser: OutputParsing {
    public init() {}

    public func parse(line: String) -> AgentEvent? {
        let clean = TerminalText.clean(line)
        guard !clean.isEmpty else { return nil }
        let lower = clean.lowercased()

        if containsAny(lower, [
            "allow this command",
            "allow once",
            "do you want to proceed",
            "do you want to run this command",
            "would you like to run the following command",
            "approve this action",
            "approval required",
            "permission required"
        ]) {
            return AgentEvent(kind: .approvalRequired, summary: clean)
        }
        if containsAny(lower, [
            "waiting for input",
            "what would you like me to do",
            "please provide",
            "enter your response",
            "press enter to continue",
            "input required"
        ]) {
            return AgentEvent(kind: .inputRequired, summary: clean)
        }
        return nil
    }

    private func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}

public struct TerminalOutputBuffer {
    private var buffer = ""

    public init() {}

    public mutating func append(_ chunk: String) -> [String] {
        buffer += chunk
        var lines: [String] = []
        while let separator = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(buffer[..<separator])
            buffer.removeSubrange(...separator)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    public mutating func flush() -> String? {
        defer { buffer = "" }
        return buffer.isEmpty ? nil : buffer
    }
}

public final class EventGate: @unchecked Sendable {
    private let cooldown: TimeInterval
    private var lastEvent: (event: AgentEvent, date: Date)?
    private let lock = NSLock()

    public init(cooldown: TimeInterval = 4) {
        self.cooldown = cooldown
    }

    public func shouldDeliver(_ event: AgentEvent, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let lastEvent,
           lastEvent.event.kind == event.kind,
           now.timeIntervalSince(lastEvent.date) < cooldown {
            return false
        }
        lastEvent = (event, now)
        return true
    }
}

public struct CompositeOutputParser: OutputParsing {
    private let parsers: [any OutputParsing]

    public init(_ parsers: [any OutputParsing]) { self.parsers = parsers }

    public func parse(line: String) -> AgentEvent? {
        parsers.lazy.compactMap { $0.parse(line: line) }.first
    }
}
