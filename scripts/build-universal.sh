#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
rm -rf dist
mkdir -p dist/arm64 dist/x86_64
swift build -c release --arch arm64 --product notchguard
cp .build/arm64-apple-macosx/release/notchguard dist/arm64/notchguard
swift build -c release --arch x86_64 --product notchguard
cp .build/x86_64-apple-macosx/release/notchguard dist/x86_64/notchguard
lipo -create -output dist/notchguard dist/arm64/notchguard dist/x86_64/notchguard
codesign --force --sign - dist/notchguard
file dist/notchguard

