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

detach_mount() {
  if hdiutil detach "$mount_dir" >/dev/null 2>&1; then
    mounted=false
    return 0
  fi
  hdiutil detach "$mount_dir" -force >/dev/null
  mounted=false
}

cleanup() {
  if [[ "$mounted" == true ]]; then
    detach_mount || true
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
mounted_iconset="$working_dir/TokenLink.iconset"
iconutil -c iconset "$mounted_app/Contents/Resources/TokenLink.icns" -o "$mounted_iconset"
cmp "$repo_dir/assets/branding/logo-mark-light.png" \
  "$mounted_iconset/icon_512x512@2x.png"
test -f "$mounted_app/Contents/Resources/TokenLink_TokenLinkApp.bundle/codex.png"
test -f \
  "$mounted_app/Contents/Resources/TokenLink_TokenLinkProviders.bundle/api-equivalent-prices.json"
test -L "$mount_dir/Applications"
test "$(readlink "$mount_dir/Applications")" = "/Applications"
cmp "$repo_dir/LICENSE" "$mounted_app/Contents/Resources/LICENSE"
cmp "$repo_dir/NOTICE" "$mounted_app/Contents/Resources/NOTICE"
lipo "$mounted_app/Contents/MacOS/TokenLink" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$mounted_app"

# Launch the exact app from the read-only mounted DMG. Resource accessors with
# build-machine-only paths fail immediately, so surviving this cold start proves
# the distributed bundle can initialize before it reaches a user's Applications
# folder. Terminate only the child process started here.
launch_log="$working_dir/tokenlink-launch.log"
"$mounted_app/Contents/MacOS/TokenLink" >"$launch_log" 2>&1 &
launch_pid=$!
sleep 3
if ! kill -0 "$launch_pid" 2>/dev/null; then
  wait "$launch_pid" || launch_status=$?
  cat "$launch_log" >&2
  echo "Mounted TokenLink app exited during cold-start smoke test (status ${launch_status:-0})." >&2
  exit 1
fi
kill "$launch_pid"
wait "$launch_pid" 2>/dev/null || true
if grep -F "could not load resource bundle" "$launch_log" >/dev/null; then
  cat "$launch_log" >&2
  echo "Mounted TokenLink app could not resolve a SwiftPM resource bundle." >&2
  exit 1
fi

if [[ -n "$notary_profile" ]]; then
  spctl --assess --type execute --verbose=2 "$mounted_app"
fi

detach_mount

(cd "$dist_dir" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$checksum")")
(cd "$dist_dir" && shasum -a 256 -c "$(basename "$checksum")" >/dev/null)

echo "Created $dmg"
echo "Created $checksum"
