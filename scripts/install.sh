#!/usr/bin/env bash
set -euo pipefail

repository="siddnikh/notchguard"
install_dir="${NOTCHGUARD_INSTALL_DIR:-$HOME/.local/bin}"
release_url="https://github.com/$repository/releases/latest/download/notchguard"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/notchguard.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Notchguard requires macOS 13 or newer." >&2
  exit 1
fi

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$macos_major" -lt 13 ]]; then
  echo "Notchguard requires macOS 13 or newer. This Mac is running $(sw_vers -productVersion)." >&2
  exit 1
fi

echo "Installing Notchguard…"
curl --fail --silent --show-error --location "$release_url" --output "$temporary/notchguard"

if ! file "$temporary/notchguard" | grep -q "Mach-O universal binary"; then
  echo "The downloaded release is not a universal macOS binary." >&2
  exit 1
fi

chmod 755 "$temporary/notchguard"
codesign --verify "$temporary/notchguard"
mkdir -p "$install_dir"
install -m 755 "$temporary/notchguard" "$install_dir/.notchguard.installing"
mv -f "$install_dir/.notchguard.installing" "$install_dir/notchguard"

echo "Installed to $install_dir/notchguard"
if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  echo
  echo "Add Notchguard to your PATH once:"
  echo "  echo 'export PATH=\"$install_dir:\$PATH\"' >> ~/.zprofile"
  echo "  source ~/.zprofile"
fi
echo
echo "Then start the agent you already use:"
echo "  notchguard claude"
echo "  notchguard codex"
