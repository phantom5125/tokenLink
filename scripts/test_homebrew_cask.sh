#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
validation_dir="$repo_dir/.build/homebrew-contract"
sha256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
community_cask="$validation_dir/community/tokenlink.rb"
notarized_cask="$validation_dir/notarized/tokenlink.rb"

bash "$repo_dir/scripts/render_homebrew_cask.sh" \
  0.3.0 "$sha256" community "$community_cask"
bash "$repo_dir/scripts/render_homebrew_cask.sh" \
  0.3.0 "$sha256" notarized "$notarized_cask"

ruby -c "$community_cask" >/dev/null
ruby -c "$notarized_cask" >/dev/null
grep -F 'version "0.3.0"' "$community_cask" >/dev/null
grep -F "sha256 \"$sha256\"" "$community_cask" >/dev/null
grep -F "community-funded build is ad-hoc signed" "$community_cask" >/dev/null
if grep -F "caveats <<~EOS" "$notarized_cask" >/dev/null; then
  echo "Notarized cask unexpectedly contains the community warning." >&2
  exit 1
fi
if bash "$repo_dir/scripts/render_homebrew_cask.sh" \
  0.3 "$sha256" community "$validation_dir/invalid-version.rb" >/dev/null 2>&1; then
  echo "Renderer accepted an invalid stable version." >&2
  exit 1
fi
if bash "$repo_dir/scripts/render_homebrew_cask.sh" \
  0.3.0 deadbeef community "$validation_dir/invalid-sha.rb" >/dev/null 2>&1; then
  echo "Renderer accepted an invalid SHA-256." >&2
  exit 1
fi

echo "Homebrew cask contract passed."
