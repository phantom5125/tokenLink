#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -n "${TOKENLINK_PIO:-}" ]]; then
  exec "$TOKENLINK_PIO" "$@"
fi

if [[ -x "$repo_dir/.venv-pio/bin/pio" ]]; then
  exec "$repo_dir/.venv-pio/bin/pio" "$@"
fi

if command -v pio >/dev/null 2>&1; then
  exec pio "$@"
fi

if command -v platformio >/dev/null 2>&1; then
  exec platformio "$@"
fi

cat >&2 <<'EOF'
PlatformIO Core 6.1.19 was not found.

Install it in this repository with:
  python3.12 -m venv .venv-pio
  .venv-pio/bin/python -m pip install platformio==6.1.19

Or set TOKENLINK_PIO to an existing pio executable.
EOF
exit 1
