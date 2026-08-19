#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"

failed=0
user_path_pattern="$(printf '/%s/' 'Users')"
uuid_pattern='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
service_uuid='7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01'
write_uuid='7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02'
zero_uuid='00000000-0000-0000-0000-00000000000[0-9]'

scan_paths=(-- ':!docs/**' ':!Tests/**' ':!scripts/privacy_scan.sh')

if matches="$(git grep -nI -F "$user_path_pattern" "${scan_paths[@]}" || true)"; [[ -n "$matches" ]]; then
  echo "Privacy scan: absolute user path found:" >&2
  echo "$matches" >&2
  failed=1
fi

uuid_matches="$(git grep -nIE "$uuid_pattern" "${scan_paths[@]}" || true)"
if [[ -n "$uuid_matches" ]]; then
  unexpected="$(printf '%s\n' "$uuid_matches" \
    | grep -Ev "$service_uuid|$write_uuid|$zero_uuid" || true)"
  if [[ -n "$unexpected" ]]; then
    echo "Privacy scan: unexpected UUID found:" >&2
    echo "$unexpected" >&2
    failed=1
  fi
fi

if matches="$(git grep -nIE 'Authorization:[[:space:]]*Bearer[[:space:]]+[^<${][^[:space:]]*' "${scan_paths[@]}" || true)"; [[ -n "$matches" ]]; then
  echo "Privacy scan: credential-bearing Authorization header found:" >&2
  echo "$matches" >&2
  failed=1
fi

if matches="$(git grep -nIE '(sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[0-9A-Za-z]{20,})' "${scan_paths[@]}" || true)"; [[ -n "$matches" ]]; then
  echo "Privacy scan: common secret prefix found:" >&2
  echo "$matches" >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo "Privacy scan passed."
