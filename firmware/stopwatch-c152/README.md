# M5Stack StopWatch C152 firmware

This is TokenLink's default wireless firmware for the M5Stack StopWatch Dev Kit
C152. It renders the Home, Quota, Sessions, and System pages and exposes both the
legacy HID-compatible controls and TokenLink's private BLE protocol v1/v2 GATT
service.

The subtree was imported from the firmware revision used by the TokenLink 0.2.0
release-candidate line. It preserves the upstream MIT attribution in `LICENSE`
and `NOTICE.md`; Space Mono remains under the OFL in `assets/fonts/OFL.txt`.
TokenLink does not use an external checkout, submodule, or binary blob to build
this target.

Run build, test, package, and flash commands from the TokenLink repository root;
see [`../README.md`](../README.md). The only release target in v0.2.2 is
`m5stack-stopwatch`. Source hooks for an earlier USB-microphone experiment remain
compile-time disabled and are not a supported build variant.
