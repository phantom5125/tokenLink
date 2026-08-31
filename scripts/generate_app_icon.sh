#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_png="$repo_dir/assets/branding/logo-mark-light.png"
output_icns="${1:-$repo_dir/packaging/TokenLink.icns}"
working_dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenlink-app-icon.XXXXXX")"
trap 'rm -rf "$working_dir"' EXIT

if [[ ! -f "$source_png" ]]; then
  echo "Canonical branding asset was not found at $source_png" >&2
  exit 1
fi

iconset="$working_dir/TokenLink.iconset"
mkdir -p "$iconset"

resize_brand_asset() {
  local pixels="$1"
  local filename="$2"
  sips --resampleHeightWidth "$pixels" "$pixels" "$source_png" \
    --out "$iconset/$filename" >/dev/null
}

resize_brand_asset 16 icon_16x16.png
resize_brand_asset 32 icon_16x16@2x.png
resize_brand_asset 32 icon_32x32.png
resize_brand_asset 64 icon_32x32@2x.png
resize_brand_asset 128 icon_128x128.png
resize_brand_asset 256 icon_128x128@2x.png
resize_brand_asset 256 icon_256x256.png
resize_brand_asset 512 icon_256x256@2x.png
resize_brand_asset 512 icon_512x512.png
resize_brand_asset 1024 icon_512x512@2x.png

mkdir -p "$(dirname "$output_icns")"
iconutil -c icns "$iconset" -o "$output_icns"
echo "Created $output_icns"
