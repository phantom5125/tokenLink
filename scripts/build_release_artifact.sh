#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$repo_dir/TokenLink.app"
dist_dir="$repo_dir/dist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/packaging/Info.plist")"
architecture="$(uname -m)"
archive="$dist_dir/TokenLink-$version-macos-$architecture.zip"
checksum="$archive.sha256"
working_dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenlink-release.XXXXXX")"
trap 'rm -rf "$working_dir"' EXIT

"$repo_dir/scripts/package_app.sh"

notary_profile="${TOKENLINK_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" ]]; then
  if [[ "${TOKENLINK_CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "TOKENLINK_NOTARY_PROFILE requires a Developer ID signing identity." >&2
    exit 1
  fi

  notarization_archive="$working_dir/TokenLink-notarization.zip"
  ditto -c -k --sequesterRsrc --keepParent "$bundle" "$notarization_archive"
  xcrun notarytool submit "$notarization_archive" \
    --keychain-profile "$notary_profile" \
    --wait
  xcrun stapler staple "$bundle"
  xcrun stapler validate "$bundle"
fi

mkdir -p "$dist_dir"
rm -f "$archive" "$checksum"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$archive"

verification_dir="$working_dir/verify"
mkdir -p "$verification_dir"
ditto -x -k "$archive" "$verification_dir"

extracted_app="$verification_dir/TokenLink.app"
test -x "$extracted_app/Contents/MacOS/TokenLink"
test -f "$extracted_app/Contents/Info.plist"
test -f "$extracted_app/Contents/Resources/TokenLink_TokenLinkApp.bundle/codex.png"
cmp "$repo_dir/LICENSE" "$extracted_app/Contents/Resources/LICENSE"
cmp "$repo_dir/NOTICE" "$extracted_app/Contents/Resources/NOTICE"
codesign --verify --deep --strict "$extracted_app"

(cd "$dist_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")")
(cd "$dist_dir" && shasum -a 256 -c "$(basename "$checksum")" >/dev/null)

echo "Created $archive"
echo "Created $checksum"
