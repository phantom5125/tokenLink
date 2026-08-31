# M5Stack StopWatch C152 firmware

This is TokenLink's default wireless firmware for the M5Stack StopWatch Dev Kit
C152. It renders the Home, Quota, Sessions, and System pages and exposes both the
legacy HID-compatible controls and TokenLink's private BLE protocol v1/v2 GATT
service.

The subtree was imported from the firmware revision used by the TokenLink 0.2.0
release-candidate line. It preserves the upstream MIT attribution in `LICENSE`
and `NOTICE.md`; Space Mono and the Nunito numeric dial subset remain under the
OFL in `assets/fonts/`.
TokenLink does not use an external checkout, submodule, or binary blob to build
this target.

Run build, test, package, and flash commands from the TokenLink repository root;
see [`../README.md`](../README.md). The only release target in v0.3.0 is
`m5stack-stopwatch`. Source hooks for an earlier USB-microphone experiment remain
compile-time disabled and are not a supported build variant.

The Data face home screen uses a TokenLink-style open quota arc. Its filled arc
is the actual remaining percentage; the white tick is the time-proportional
planned remainder when the Mac supplies a known window duration. Main quota and
clock numerals use an embedded ExtraBold Nunito subset, while compact labels use
Space Mono for legibility.

## Watch-face runtime capability

The C03 capabilities characteristic keeps protocol negotiation backward
compatible and now also advertises the built-in face runtime independently:

```json
{
  "protocol_versions": [1, 2],
  "firmware": "0.2.1-tokenlink",
  "features": ["face_runtime"],
  "face_runtime_versions": [1]
}
```

Runtime v1 is the shared registry and behavior boundary used by the built-in
Data and Pet faces. It does not claim support for third-party packages, asset
formats, device storage, or bulk transfer. Those capabilities remain absent
until their implementations and rollback paths exist. Older Mac clients ignore
the added JSON fields; newer clients treat missing feature fields as unsupported.
