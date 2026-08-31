#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <version> <sha256> <community|notarized> <output>" >&2
  exit 64
fi

version="$1"
sha256="$2"
distribution="$3"
output="$4"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
template="$repo_dir/packaging/homebrew/tokenlink.rb.in"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Homebrew stable version must use MAJOR.MINOR.PATCH: $version" >&2
  exit 65
fi
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Homebrew cask requires a lowercase 64-character SHA-256." >&2
  exit 65
fi
if [[ "$distribution" != "community" && "$distribution" != "notarized" ]]; then
  echo "Unsupported distribution mode: $distribution" >&2
  exit 65
fi
if [[ ! -f "$template" ]]; then
  echo "Missing Homebrew cask template: $template" >&2
  exit 66
fi

mkdir -p "$(dirname "$output")"
awk \
  -v version="$version" \
  -v sha256="$sha256" \
  -v distribution="$distribution" '
    /__TOKENLINK_CAVEATS__/ {
      if (distribution == "community") {
        print "  caveats <<~EOS"
        print "    This community-funded build is ad-hoc signed and is not Apple-notarized."
        print "    Review the source and release checksum before opening it. If macOS blocks"
        print "    the first launch, allow TokenLink in System Settings > Privacy & Security."
        print "  EOS"
      }
      next
    }
    {
      gsub(/__TOKENLINK_VERSION__/, version)
      gsub(/__TOKENLINK_SHA256__/, sha256)
      print
    }
  ' "$template" > "$output"

ruby -c "$output" >/dev/null
echo "Rendered $output for TokenLink $version ($distribution)"
