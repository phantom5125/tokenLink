#!/usr/bin/env bash
set -euo pipefail

developer_dir="$(xcode-select -p)"

if [[ "$developer_dir" == */CommandLineTools ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  interop="$developer_dir/Library/Developer/usr/lib"
  macros="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [[ -d "$frameworks/Testing.framework" && -f "$macros" ]]; then
    exec swift test \
      -Xswiftc -F -Xswiftc "$frameworks" \
      -Xswiftc -load-plugin-library -Xswiftc "$macros" \
      -Xlinker -F -Xlinker "$frameworks" \
      -Xlinker -rpath -Xlinker "$frameworks" \
      -Xlinker -rpath -Xlinker "$interop" \
      "$@"
  fi
fi

exec swift test "$@"
