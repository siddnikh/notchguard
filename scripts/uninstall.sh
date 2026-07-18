#!/usr/bin/env bash
set -euo pipefail

install_dir="${NOTCHGUARD_INSTALL_DIR:-$HOME/.local/bin}"
binary="$install_dir/notchguard"
presenter="$HOME/Library/Application Support/Notchguard/Notchguard Presenter.app"

if [[ -e "$binary" ]]; then
  rm "$binary"
  echo "Removed $binary"
else
  echo "Notchguard is not installed at $binary"
fi

if [[ -d "$presenter" ]]; then
  rm -rf "$presenter"
  echo "Removed the local presenter."
fi

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$HOME/Library/Application Support/Notchguard"
  echo "Removed installed plugins."
fi
