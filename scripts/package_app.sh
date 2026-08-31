#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$repo_dir/.build/artifacts/TokenLink.app"
app_resource_bundle_name="TokenLink_TokenLinkApp.bundle"
provider_resource_bundle_name="TokenLink_TokenLinkProviders.bundle"
build_archs_value="${TOKENLINK_BUILD_ARCHS:-$(uname -m)}"

cd "$repo_dir"
read -r -a build_archs <<< "$build_archs_value"
built_executables=()
app_resource_bundle=""
provider_resource_bundle=""

if [[ "${#build_archs[@]}" -eq 0 ]]; then
  echo "TOKENLINK_BUILD_ARCHS must contain at least one architecture." >&2
  exit 1
fi

for architecture in "${build_archs[@]}"; do
  case "$architecture" in
    arm64 | x86_64) ;;
    *)
      echo "Unsupported Mac architecture: $architecture" >&2
      exit 1
      ;;
  esac

  triple="$architecture-apple-macosx14.0"
  scratch_path="$repo_dir/.build/package-$architecture"
  swift build -c release --product tokenlink \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    -Xswiftc -DTOKENLINK_PACKAGED_APP
  release_bin_dir="$(swift build -c release \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    --show-bin-path)"
  architecture_executable="$release_bin_dir/tokenlink"
  architecture_app_resource_bundle="$release_bin_dir/$app_resource_bundle_name"
  architecture_provider_resource_bundle="$release_bin_dir/$provider_resource_bundle_name"

  if [[ ! -x "$architecture_executable" ]]; then
    echo "Release executable was not produced at $architecture_executable" >&2
    exit 1
  fi

  if [[ ! -d "$architecture_app_resource_bundle" ]]; then
    echo "SwiftPM resource bundle was not produced at $architecture_app_resource_bundle" >&2
    exit 1
  fi

  if [[ ! -d "$architecture_provider_resource_bundle" ]]; then
    echo "SwiftPM resource bundle was not produced at $architecture_provider_resource_bundle" >&2
    exit 1
  fi

  built_executables+=("$architecture_executable")
  if [[ -z "$app_resource_bundle" ]]; then
    app_resource_bundle="$architecture_app_resource_bundle"
    provider_resource_bundle="$architecture_provider_resource_bundle"
  fi
done

if [[ "${#built_executables[@]}" -eq 1 ]]; then
  executable="${built_executables[0]}"
else
  universal_dir="$repo_dir/.build/package-universal"
  executable="$universal_dir/tokenlink"
  mkdir -p "$universal_dir"
  lipo -create "${built_executables[@]}" -output "$executable"
  for architecture in "${build_archs[@]}"; do
    lipo "$executable" -verify_arch "$architecture"
  done
fi

if [[ "$bundle" != "$repo_dir/.build/artifacts/TokenLink.app" ]]; then
  echo "Refusing to replace an unexpected bundle path." >&2
  exit 1
fi

mkdir -p "$(dirname "$bundle")"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
generated_app_icon="$repo_dir/.build/artifacts/TokenLink.icns"
"$repo_dir/scripts/generate_app_icon.sh" "$generated_app_icon"
cp "$repo_dir/packaging/Info.plist" "$bundle/Contents/Info.plist"
cp "$executable" "$bundle/Contents/MacOS/TokenLink"
cp "$generated_app_icon" "$bundle/Contents/Resources/TokenLink.icns"
ditto "$app_resource_bundle" "$bundle/Contents/Resources/$app_resource_bundle_name"
ditto "$provider_resource_bundle" "$bundle/Contents/Resources/$provider_resource_bundle_name"
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
