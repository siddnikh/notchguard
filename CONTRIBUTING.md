# Contributing

Notchguard stays useful by staying small. Changes should improve one of three things: terminal fidelity, notification accuracy, or installation clarity.

## Before opening a pull request

```sh
swift test
./scripts/build-universal.sh
```

Please include tests for parser changes. Avoid adding network calls, analytics, background services, or support for agents beyond Claude Code and Codex without prior discussion.

Plugin rules are usually a better fit than adding a narrow output phrase to the built-in parser.

