import Foundation
import NotchguardCore
import Darwin

enum CLIError: LocalizedError {
    case usage(String)
    var errorDescription: String? {
        switch self { case .usage(let message): return message }
    }
}

@main
struct Notchguard {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("notchguard: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { throw CLIError.usage(help) }
        args.removeFirst()

        switch command {
        case "claude": try runAgent(command: "claude", arguments: args)
        case "codex": try runAgent(command: "codex", arguments: args)
        case "plugins": try plugins(arguments: args)
        case "jump": try TerminalJumper.jump(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        case "demo": demo()
        case "update": print(try SelfUpdater.update())
        case "__present": try present(arguments: args)
        case "version", "--version", "-v": print("notchguard 0.2.0")
        case "help", "--help", "-h": print(help)
        default: throw CLIError.usage("Unknown command '\(command)'.\n\n\(help)")
        }
    }

    private static func runAgent(command: String, arguments: [String]) throws {
        let notifier = NotchNotifier.shared
        let store = PluginStore()
        let parser = CompositeOutputParser([BuiltInOutputParser()] + store.parsers())
        let monitor = AgentMonitor(parser: parser) { event, session in
            notifier.send(event, session: session)
        }
        let status = try monitor.run(command: command, arguments: arguments)
        if status != 0 { exit(status) }
    }

    private static func plugins(arguments: [String]) throws {
        let store = PluginStore()
        guard let action = arguments.first else { throw CLIError.usage(pluginHelp) }
        switch action {
        case "add":
            guard let path = arguments.dropFirst().first else { throw CLIError.usage("Usage: notchguard plugins add <plugin-directory>") }
            let plugin = try store.add(bundle: URL(fileURLWithPath: path).standardizedFileURL)
            print("Installed \(plugin.name) (\(plugin.identifier))")
        case "list":
            let plugins = try store.installed()
            if plugins.isEmpty { print("No plugins installed.") }
            for plugin in plugins { print("\(plugin.manifest.identifier)  \(plugin.manifest.version)  \(plugin.manifest.name)") }
        case "remove":
            guard let identifier = arguments.dropFirst().first else { throw CLIError.usage("Usage: notchguard plugins remove <identifier>") }
            guard try store.remove(identifier: identifier) else { throw CLIError.usage("Plugin '\(identifier)' is not installed.") }
            print("Removed \(identifier)")
        default: throw CLIError.usage(pluginHelp)
        }
    }

    private static func present(arguments: [String]) throws {
        guard let encoded = arguments.first else { throw CLIError.usage("Missing presentation payload.") }
        let payload = try OverlayPayload.decode(encoded)
        NotchOverlay.shared.show(payload.event, session: payload.session)
        RunLoop.main.run(
            until: Date(timeIntervalSinceNow: NotchOverlay.displayDuration(for: payload.event.kind) + 0.4)
        )
    }

    private static func demo() {
        let tty: String?
        if isatty(STDIN_FILENO) != 0, let pointer = ttyname(STDIN_FILENO) {
            tty = String(cString: pointer)
        } else {
            tty = nil
        }
        let session = AgentSession(
            agentName: "Notchguard",
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            terminalTTY: tty
        )
        NotchNotifier.shared.send(
            AgentEvent(kind: .completed, summary: "Start with the agent you already use."),
            session: session
        )
        print("Notchguard is ready.")
    }

    private static let help = """
    Notchguard — quiet macOS notifications for Claude Code and Codex.

    Usage:
      notchguard claude [claude arguments...]
      notchguard codex [codex arguments...]
      notchguard plugins <add|list|remove> [...]
      notchguard jump
      notchguard demo
      notchguard update

    Only Claude Code and Codex are launched by this wrapper.
    """
    private static let pluginHelp = """
    Usage:
      notchguard plugins add <plugin-directory>
      notchguard plugins list
      notchguard plugins remove <identifier>
    """
}
