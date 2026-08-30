#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
firmware_dir="$repo_dir/firmware/stopwatch-c152"
output_dir="$repo_dir/dist/firmware"
version="$(/usr/bin/sed -n 's/.*kFirmwareVersion\[\] = "\([0-9][0-9.]*\)-tokenlink".*/\1/p' "$firmware_dir/include/CodexMicroBle.h")"
packaging_python="python3"

if [[ -x "$repo_dir/.venv-pio/bin/python" ]]; then
  packaging_python="$repo_dir/.venv-pio/bin/python"
fi

if [[ -z "$version" ]]; then
  echo "Could not resolve the embedded C152 firmware version." >&2
  exit 1
fi

"$repo_dir/scripts/pio.sh" run -d "$firmware_dir" -e m5stack-stopwatch
"$packaging_python" "$repo_dir/scripts/package_firmware_release.py" \
  --version "$version" \
  --output "$output_dir" \
  --pio "$repo_dir/scripts/pio.sh"

echo "Created C152 release artifacts in $output_dir"
