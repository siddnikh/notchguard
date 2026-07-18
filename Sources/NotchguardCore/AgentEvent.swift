import Foundation

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

    public var title: String {
        switch kind {
        case .inputRequired: return "Input required"
        case .approvalRequired: return "Approval required"
        case .completed: return "Task finished"
        case .failed: return "Agent stopped"
        }
    }
}

public protocol OutputParsing: Sendable {
    func parse(line: String) -> AgentEvent?
}

public struct BuiltInOutputParser: OutputParsing {
    public init() {}

    public func parse(line: String) -> AgentEvent? {
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let lower = clean.lowercased()

        if containsAny(lower, ["allow this", "allow once", "do you want to proceed", "approve", "permission required"]) {
            return AgentEvent(kind: .approvalRequired, summary: clean)
        }
        if containsAny(lower, ["waiting for input", "what would you like", "please provide", "enter your", "press enter to continue", "input required"]) {
            return AgentEvent(kind: .inputRequired, summary: clean)
        }
        if containsAny(lower, ["task completed", "task complete", "successfully completed", "all done"]) {
            return AgentEvent(kind: .completed, summary: clean)
        }
        if containsAny(lower, ["fatal error", "command failed", "process exited with code", "uncaught exception"]) {
            return AgentEvent(kind: .failed, summary: clean)
        }
        return nil
    }

    private func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}

public struct CompositeOutputParser: OutputParsing {
    private let parsers: [any OutputParsing]

    public init(_ parsers: [any OutputParsing]) { self.parsers = parsers }

    public func parse(line: String) -> AgentEvent? {
        parsers.lazy.compactMap { $0.parse(line: line) }.first
    }
}

