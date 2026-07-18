import Foundation

public enum SelfUpdater {
    public static let releaseURL = URL(string: "https://github.com/siddnikh/notchguard/releases/latest/download/notchguard")!

    /// Replaces a directly installed binary with the latest public GitHub release.
    /// It deliberately does nothing automatically: a person must invoke the command.
    public static func update() throws -> String {
        let destination = executableURL()
        let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw UpdateError.symbolicLink(destination.path)
        }
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            throw UpdateError.notWritable(destination.path)
        }

        let data = try Data(contentsOf: releaseURL)
        guard data.count > 100_000, isMachO(data) else { throw UpdateError.invalidDownload }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".notchguard-update-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            guard try hasValidSignature(temporary) else { throw UpdateError.invalidSignature }
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return "Updated Notchguard at \(destination.path)."
    }

    private static func executableURL() -> URL {
        let argument = CommandLine.arguments[0]
        if argument.contains("/") {
            return URL(fileURLWithPath: argument, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        if let found = paths
            .map({ URL(fileURLWithPath: String($0)).appendingPathComponent(argument) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        return URL(fileURLWithPath: argument, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    static func isMachO(_ data: Data) -> Bool {
        let magic = data.prefix(4)
        return magic == Data([0xCA, 0xFE, 0xBA, 0xBE]) || // universal, big endian
            magic == Data([0xCA, 0xFE, 0xBA, 0xBF]) ||
            magic == Data([0xCF, 0xFA, 0xED, 0xFE]) || // 64-bit, little endian
            magic == Data([0xFE, 0xED, 0xFA, 0xCF])
    }

    private static func hasValidSignature(_ binary: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", binary.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

public enum UpdateError: LocalizedError {
    case symbolicLink(String)
    case notWritable(String)
    case invalidDownload
    case invalidSignature

    public var errorDescription: String? {
        switch self {
        case .symbolicLink(let path):
            return "Refusing to replace symbolic link \(path). Update its target manually."
        case .notWritable(let path):
            return "Notchguard is not writable at \(path). Reinstall with a writable destination."
        case .invalidDownload:
            return "The release download was not a valid Notchguard macOS binary."
        case .invalidSignature:
            return "The release download did not pass macOS code-signature verification."
        }
    }
}
