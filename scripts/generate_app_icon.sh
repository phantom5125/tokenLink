#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_icns="$repo_dir/packaging/TokenLink.icns"
working_dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenlink-app-icon.XXXXXX")"
trap 'rm -rf "$working_dir"' EXIT

iconset="$working_dir/TokenLink.iconset"
mkdir -p "$iconset"

render_size() {
  local pixels="$1"
  local filename="$2"
  xcrun swift "$repo_dir/scripts/render_app_icon.swift" "$iconset/$filename" "$pixels"
}

render_size 16 icon_16x16.png
render_size 32 icon_16x16@2x.png
render_size 32 icon_32x32.png
render_size 64 icon_32x32@2x.png
render_size 128 icon_128x128.png
render_size 256 icon_128x128@2x.png
render_size 256 icon_256x256.png
render_size 512 icon_256x256@2x.png
render_size 512 icon_512x512.png
render_size 1024 icon_512x512@2x.png

iconutil -c icns "$iconset" -o "$output_icns"
echo "Created $output_icns"
