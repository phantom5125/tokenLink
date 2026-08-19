#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$repo_dir/TokenLink.app"

cd "$repo_dir"
swift build -c release --product tokenlink

if [[ "$bundle" != "$repo_dir/TokenLink.app" ]]; then
  echo "Refusing to replace an unexpected bundle path." >&2
  exit 1
fi

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$repo_dir/packaging/Info.plist" "$bundle/Contents/Info.plist"
cp "$repo_dir/.build/release/tokenlink" "$bundle/Contents/MacOS/TokenLink"
chmod 755 "$bundle/Contents/MacOS/TokenLink"

codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
echo "Created $bundle"
