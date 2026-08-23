#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
swift build -c release --product tokenlink
bundle="$repo_dir/TokenLink.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$repo_dir/packaging/Info.plist" "$bundle/Contents/Info.plist"
cp "$repo_dir/.build/release/tokenlink" "$bundle/Contents/MacOS/TokenLink"
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
