#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"

maximum_rss_bytes=167772160
maximum_elapsed_seconds=30
maximum_executable_bytes=15728640

resource_tmp="$(mktemp -d)"
measurement_file="$resource_tmp/measurement.txt"
workload_output="$resource_tmp/workload.txt"

cleanup() {
  rm -f "$measurement_file" "$workload_output"
  rmdir "$resource_tmp" 2>/dev/null || true
}
trap cleanup EXIT

if ! swift build -c release >/dev/null 2>&1; then
  echo "Resource check: release build failed." >&2
  exit 1
fi
test_build=(swift build --build-tests)
developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == */CommandLineTools ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  interop="$developer_dir/Library/Developer/usr/lib"
  macros="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [[ -d "$frameworks/Testing.framework" && -f "$macros" ]]; then
    test_build+=(
      -Xswiftc -F -Xswiftc "$frameworks"
      -Xswiftc -load-plugin-library -Xswiftc "$macros"
      -Xlinker -F -Xlinker "$frameworks"
      -Xlinker -rpath -Xlinker "$frameworks"
      -Xlinker -rpath -Xlinker "$interop"
    )
  fi
fi
if ! "${test_build[@]}" >/dev/null 2>&1; then
  echo "Resource check: test build failed." >&2
  exit 1
fi

set +e
/usr/bin/time -l env TOKENLINK_RESOURCE_WORKLOAD=1 \
  bash scripts/test.sh --skip-build --filter LocalCostResourceTests \
  >"$workload_output" 2>"$measurement_file"
workload_status=$?
set -e

if [[ $workload_status -ne 0 ]]; then
  echo "Resource check: workload failed." >&2
  exit 1
fi

maximum_rss="$(awk '/maximum resident set size/ { print $1; exit }' "$measurement_file")"
elapsed_seconds="$(awk '/ real / { print $1; exit }' "$measurement_file")"
executable_bytes="$(stat -f '%z' .build/release/tokenlink)"

if [[ -z "$maximum_rss" || -z "$elapsed_seconds" || -z "$executable_bytes" ]]; then
  echo "Resource check: measurement unavailable." >&2
  exit 1
fi

printf 'Resource workload: %s seconds\n' "$elapsed_seconds"
printf 'Maximum RSS: %s bytes\n' "$maximum_rss"
printf 'Release executable: %s bytes\n' "$executable_bytes"

failed=0
if (( maximum_rss > maximum_rss_bytes )); then
  echo "Resource check: RSS limit exceeded." >&2
  failed=1
fi
if ! awk -v actual="$elapsed_seconds" -v limit="$maximum_elapsed_seconds" \
  'BEGIN { exit !(actual <= limit) }'; then
  echo "Resource check: elapsed-time limit exceeded." >&2
  failed=1
fi
if (( executable_bytes > maximum_executable_bytes )); then
  echo "Resource check: executable-size limit exceeded." >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo "Resource check passed."
