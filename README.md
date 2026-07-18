# Notchguard

Leave the terminal. Come back when your agent actually needs you.

Notchguard wraps **Claude Code** and **Codex** on macOS. It preserves the real interactive session, stays silent while work is moving, and places one compact cue beneath the notch for approval, input, completion, or failure.

## Install

macOS 13 or newer. No Xcode and no sudo required.

```sh
curl -fsSL https://raw.githubusercontent.com/siddnikh/notchguard/main/scripts/install.sh | bash
```

The installer places the universal Apple Silicon + Intel binary in `~/.local/bin`, tells you if that directory needs adding to your `PATH`, and shows one short ready cue so you know the notch presentation works.

## Use

Put `notchguard` before the command you already run:

```sh
notchguard claude
notchguard codex
```

Arguments pass through unchanged:

```sh
notchguard claude "review the open changes"
notchguard codex "explain this failing test"
```

Run `notchguard demo` whenever you want to check the presentation without starting an agent.

That is the whole daily workflow. The child process keeps the current directory, environment, pseudo-terminal interaction, output, input, and exit status. When attention is needed, **Return** brings the original Terminal tab forward; if that tab is gone, Terminal opens at the project directory.

## Quiet by design

- No menu bar item, settings window, account, daemon, or analytics.
- No prompt or terminal-output storage.
- No network access during agent sessions.
- Only the explicit `notchguard update` command contacts this repository.

Notchguard launches only Claude Code and Codex. It does not install, authenticate, or configure either agent.

## Update or remove

```sh
notchguard update
```

Updates are manual and replace a directly installed, writable binary atomically. Package-managed symlinks are left alone.

```sh
curl -fsSL https://raw.githubusercontent.com/siddnikh/notchguard/main/scripts/uninstall.sh | bash
```

Add `--purge` when running `scripts/uninstall.sh` locally to remove installed parser plugins as well.

## Parser plugins

Plugins extend output detection with local, declarative rules. They cannot execute code.

```sh
notchguard plugins add ./my-parser.notchplugin
notchguard plugins list
notchguard plugins remove my-team.parser
```

A plugin is a directory ending in `.notchplugin` with a `plugin.json`:

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

Supported events are `input_required`, `approval_required`, `completed`, and `failed`. Patterns are case-insensitive regular expressions. See the working example in [`Examples/waiting-for-review.notchplugin`](Examples/waiting-for-review.notchplugin).

## Build from source

Building requires Xcode or matching Xcode Command Line Tools:

```sh
swift test
./scripts/build-universal.sh
```

The universal, ad-hoc-signed binary is written to `dist/notchguard`. Notchguard targets macOS 13+ and has no package dependencies.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a feature. Report vulnerabilities through GitHub's private vulnerability reporting process described in [SECURITY.md](SECURITY.md).

MIT licensed. See [LICENSE](LICENSE).
