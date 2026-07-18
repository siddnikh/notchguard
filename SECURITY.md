# Security

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository rather than opening a public issue. Include the affected version, impact, and a minimal reproduction when possible.

## Security model

Notchguard runs the locally installed agent command with the current terminal's environment and working directory. It does not inspect prompts beyond in-memory output matching, retain terminal output, run plugin code, collect analytics, or operate a background service.

Plugins are declarative regular-expression manifests copied into `~/Library/Application Support/Notchguard/plugins`. The manual updater downloads the universal binary from this repository's latest GitHub release over HTTPS and validates that it is a signed Mach-O binary before replacement.

