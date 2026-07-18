import Foundation

public struct PluginManifest: Codable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let rules: [PluginRule]

    public init(identifier: String, name: String, version: String, rules: [PluginRule]) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.rules = rules
    }
}

public struct PluginRule: Codable, Equatable, Sendable {
    public let pattern: String
    public let event: AgentEventKind
    public let summary: String?

    public init(pattern: String, event: AgentEventKind, summary: String? = nil) {
        self.pattern = pattern
        self.event = event
        self.summary = summary
    }
}

public struct PluginOutputParser: OutputParsing {
    public let manifest: PluginManifest
    private let compiledRules: [(PluginRule, NSRegularExpression)]

    public init(manifest: PluginManifest) throws {
        self.manifest = manifest
        self.compiledRules = try manifest.rules.map { rule in
            (rule, try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]))
        }
    }

    public func parse(line: String) -> AgentEvent? {
        let range = NSRange(line.startIndex..., in: line)
        for (rule, expression) in compiledRules where expression.firstMatch(in: line, range: range) != nil {
            return AgentEvent(kind: rule.event, summary: rule.summary ?? line)
        }
        return nil
    }
}

public enum PluginError: LocalizedError {
    case invalidBundle(String)
    case duplicateIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBundle(let message): return message
        case .duplicateIdentifier(let id): return "A plugin with identifier '\(id)' is already installed."
        }
    }
}

public struct PluginStore {
    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL = PluginStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notchguard/plugins", isDirectory: true)
    }

    public func installed() throws -> [(manifest: PluginManifest, location: URL)] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "notchplugin" }
            .compactMap { url in
                let manifestURL = url.appendingPathComponent("plugin.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else { return nil }
                return (manifest, url)
            }
    }

    public func parsers() -> [any OutputParsing] {
        (try? installed().compactMap { try? PluginOutputParser(manifest: $0.manifest) }) ?? []
    }

    @discardableResult
    public func add(bundle source: URL) throws -> PluginManifest {
        let manifestURL = source.appendingPathComponent("plugin.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PluginError.invalidBundle("Expected a plugin.json inside \(source.path).")
        }
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.identifier.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw PluginError.invalidBundle("Plugin identifiers use lowercase letters, numbers, dots, and dashes.")
        }
        try PluginOutputParser(manifest: manifest)
        if try installed().contains(where: { $0.manifest.identifier == manifest.identifier }) {
            throw PluginError.duplicateIdentifier(manifest.identifier)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(manifest.identifier).notchplugin", isDirectory: true)
        try fileManager.copyItem(at: source, to: destination)
        return manifest
    }

    public func remove(identifier: String) throws -> Bool {
        let match = try installed().first { $0.manifest.identifier == identifier }
        guard let match else { return false }
        try fileManager.removeItem(at: match.location)
        return true
    }
}

