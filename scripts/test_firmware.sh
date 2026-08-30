#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
firmware_dir="$repo_dir/firmware/stopwatch-c152"
build_dir="$firmware_dir/.pio/build/m5stack-stopwatch"
arduino_json="$firmware_dir/.pio/libdeps/m5stack-stopwatch/ArduinoJson/src"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenlink-firmware-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

"$repo_dir/scripts/pio.sh" run -d "$firmware_dir" -e m5stack-stopwatch

if [[ ! -d "$arduino_json" ]]; then
  echo "ArduinoJson headers were not installed at $arduino_json" >&2
  exit 1
fi

plain_tests=(
  completion_banner_test
  connection_health_test
  gesture_test
  power_button_input_test
  power_button_gesture_test
  raise_wake_test
  watch_protocol_presentation_test
)

json_tests=(
  host_rpc_request_test
  quota_payload_test
  session_presentation_test
  watch_model_test
  watch_protocol_v2_test
)

for test_name in "${plain_tests[@]}"; do
  c++ -std=c++17 -I"$firmware_dir/include" \
    "$firmware_dir/simulator/$test_name.cpp" -o "$test_dir/$test_name"
  "$test_dir/$test_name"
done

for test_name in "${json_tests[@]}"; do
  c++ -std=c++17 -I"$firmware_dir/include" -I"$arduino_json" \
    "$firmware_dir/simulator/$test_name.cpp" -o "$test_dir/$test_name"
  "$test_dir/$test_name"
done

for required in bootloader.bin partitions.bin boot_app0.bin firmware.bin firmware.elf; do
  test -f "$build_dir/$required"
done

echo "C152 firmware build and simulator tests passed."
