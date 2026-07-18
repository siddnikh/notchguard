# Notchguard

Notchguard is a small native macOS wrapper for **Claude Code** and **Codex**. It watches terminal output for the moments that need you — input, approval, completion, or a failure — then places a compact native panel under the notch. One click opens Terminal at the working directory; the normal macOS banner is kept as an accessible fallback.

It deliberately launches only Claude Code and Codex. It does not send prompts, terminal output, or telemetry anywhere.

## Install

Requirements: macOS 13 (Ventura) or newer, Xcode Command Line Tools, and either the `claude` or `codex` command already installed and authenticated.

```sh
git clone https://github.com/YOUR-GITHUB-USER/notchguard.git
cd notchguard
swift build -c release
install -m 755 .build/release/notchguard /usr/local/bin/notchguard
```

For a universal Apple Silicon + Intel binary:

```sh
./scripts/build-universal.sh
install -m 755 dist/notchguard /usr/local/bin/notchguard
```

## Use

Use the same agent commands you normally use, with `notchguard` in front:

```sh
notchguard claude
notchguard claude "review the open changes"
notchguard codex
notchguard codex "explain this failing test"
```

The wrapped process retains your current directory, environment, standard input, exit status, and output. It is launched through a pseudo-terminal, so interactive Claude Code and Codex flows continue to behave like a terminal session. On first run macOS asks whether Notchguard may show notifications. Notchguard only notifies for an interaction boundary; normal streaming output stays silent.

`notchguard jump` activates Terminal and opens the current directory using AppleScript, falling back to `open -a Terminal` when needed.

## Update

Updates are always manual. `notchguard update` downloads the latest universal binary from this repository's public releases and atomically replaces a directly installed, writable binary. It refuses to replace symbolic links, so package-managed installs stay under their package manager's control.

```sh
notchguard update
```

## Plugins

Plugins are local folders ending in `.notchplugin` with a `plugin.json` manifest. They add parser rules without running arbitrary plugin code.

```sh
notchguard plugins add Examples/waiting-for-review.notchplugin
notchguard plugins list
notchguard plugins remove example.waiting-for-review
```

Installed plugins live in `~/Library/Application Support/Notchguard/plugins`.

```json
{
  "identifier": "my-team.release-gate",
  "name": "Release gate",
  "version": "1.0.0",
  "rules": [
    {
      "pattern": "TYPE_RELEASE_APPROVAL",
      "event": "approval_required",
      "summary": "Release approval is waiting"
    }
  ]
}
```

Supported events are `input_required`, `approval_required`, `completed`, and `failed`. Patterns are case-insensitive regular expressions. A malformed plugin is rejected on install.

## Development

```sh
swift test
swift run notchguard --help
```

The project is a dependency-free Swift Package, targeted at macOS 13+. `scripts/build-universal.sh` produces a universal binary appropriate for packaging in a signed `.pkg`, a Homebrew tap, or a Sparkle-enabled app wrapper.

## Privacy

Notchguard has no analytics or background daemon. Output is parsed in memory and only the short, relevant line becomes the local notification body. The sole network operation is the explicit `notchguard update` command, which downloads the public release binary from this repository.

## License

[MIT](LICENSE)
