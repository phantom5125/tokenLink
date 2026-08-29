#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$repo_dir/TokenLink.app"
resource_bundle_name="TokenLink_TokenLinkApp.bundle"

cd "$repo_dir"
swift build -c release --product tokenlink
release_bin_dir="$(swift build -c release --show-bin-path)"
executable="$release_bin_dir/tokenlink"
resource_bundle="$release_bin_dir/$resource_bundle_name"

if [[ ! -x "$executable" ]]; then
  echo "Release executable was not produced at $executable" >&2
  exit 1
fi

if [[ ! -d "$resource_bundle" ]]; then
  echo "SwiftPM resource bundle was not produced at $resource_bundle" >&2
  exit 1
fi

if [[ "$bundle" != "$repo_dir/TokenLink.app" ]]; then
  echo "Refusing to replace an unexpected bundle path." >&2
  exit 1
fi

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$repo_dir/packaging/Info.plist" "$bundle/Contents/Info.plist"
cp "$executable" "$bundle/Contents/MacOS/TokenLink"
ditto "$resource_bundle" "$bundle/Contents/Resources/$resource_bundle_name"
cp "$repo_dir/LICENSE" "$bundle/Contents/Resources/LICENSE"
cp "$repo_dir/NOTICE" "$bundle/Contents/Resources/NOTICE"
chmod 755 "$bundle/Contents/MacOS/TokenLink"

plutil -lint "$bundle/Contents/Info.plist" >/dev/null

signing_identity="${TOKENLINK_CODESIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --deep --sign - "$bundle"
else
  codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$bundle"
fi
codesign --verify --deep --strict "$bundle"
echo "Created $bundle"
