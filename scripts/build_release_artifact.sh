#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$repo_dir/.build/artifacts/TokenLink.app"
dist_dir="$repo_dir/dist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/packaging/Info.plist")"
dmg="$dist_dir/TokenLink-$version.dmg"
checksum="$dmg.sha256"
working_dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenlink-release.XXXXXX")"
mount_dir="$working_dir/mount"
mounted=false

cleanup() {
  if [[ "$mounted" == true ]]; then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  rm -rf "$working_dir"
}
trap cleanup EXIT

TOKENLINK_BUILD_ARCHS="${TOKENLINK_BUILD_ARCHS:-arm64 x86_64}" \
  "$repo_dir/scripts/package_app.sh"

notary_profile="${TOKENLINK_NOTARY_PROFILE:-}"
notary_keychain="${TOKENLINK_NOTARY_KEYCHAIN:-}"
if [[ -n "$notary_profile" ]]; then
  if [[ "${TOKENLINK_CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "TOKENLINK_NOTARY_PROFILE requires a Developer ID signing identity." >&2
    exit 1
  fi

  notarization_archive="$working_dir/TokenLink-notarization.zip"
  ditto -c -k --sequesterRsrc --keepParent "$bundle" "$notarization_archive"
  notary_options=(--keychain-profile "$notary_profile")
  if [[ -n "$notary_keychain" ]]; then
    notary_options+=(--keychain "$notary_keychain")
  fi
  xcrun notarytool submit "$notarization_archive" \
    "${notary_options[@]}" \
    --wait
  xcrun stapler staple "$bundle"
  xcrun stapler validate "$bundle"
fi

mkdir -p "$dist_dir"
rm -f "$dmg" "$checksum"

dmg_root="$working_dir/dmg-root"
mkdir -p "$dmg_root"
ditto "$bundle" "$dmg_root/TokenLink.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create \
  -volname "TokenLink $version" \
  -srcfolder "$dmg_root" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$dmg"

if [[ -n "$notary_profile" ]]; then
  codesign --force --timestamp --sign "$TOKENLINK_CODESIGN_IDENTITY" "$dmg"
  xcrun notarytool submit "$dmg" \
    "${notary_options[@]}" \
    --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
fi

hdiutil verify "$dmg"
mkdir -p "$mount_dir"
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount_dir" >/dev/null
mounted=true

mounted_app="$mount_dir/TokenLink.app"
test -x "$mounted_app/Contents/MacOS/TokenLink"
test -f "$mounted_app/Contents/Info.plist"
test -f "$mounted_app/Contents/Resources/TokenLink.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$mounted_app/Contents/Info.plist")" = \
  "TokenLink.icns"
test -f "$mounted_app/Contents/Resources/TokenLink_TokenLinkApp.bundle/codex.png"
test -f \
  "$mounted_app/Contents/Resources/TokenLink_TokenLinkProviders.bundle/api-equivalent-prices.json"
test -L "$mount_dir/Applications"
test "$(readlink "$mount_dir/Applications")" = "/Applications"
cmp "$repo_dir/LICENSE" "$mounted_app/Contents/Resources/LICENSE"
cmp "$repo_dir/NOTICE" "$mounted_app/Contents/Resources/NOTICE"
lipo "$mounted_app/Contents/MacOS/TokenLink" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$mounted_app"

if [[ -n "$notary_profile" ]]; then
  spctl --assess --type execute --verbose=2 "$mounted_app"
fi

hdiutil detach "$mount_dir" >/dev/null
mounted=false

(cd "$dist_dir" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$checksum")")
(cd "$dist_dir" && shasum -a 256 -c "$(basename "$checksum")" >/dev/null)

echo "Created $dmg"
echo "Created $checksum"
