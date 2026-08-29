# TokenLink firmware

This directory is the source catalog for hardware that speaks the TokenLink
watch protocol. The first supported target is the M5Stack StopWatch Dev Kit
C152. Future devices should live in their own sibling directory and declare
their product, protocol, build, and release mapping in `catalog.json`.

```text
firmware/
├── catalog.json             source/build registry for supported hardware
└── stopwatch-c152/          independently licensed PlatformIO project
    ├── include/ and src/    firmware and round-display UI
    ├── simulator/           host-native model/protocol tests
    ├── partitions/          repository-owned flash layout
    ├── assets/fonts/        Space Mono source and OFL license
    ├── LICENSE              MIT license for this firmware subtree
    └── NOTICE.md            attribution and compatibility boundaries
```

The Mac app owns provider access, quota normalization, Codex task discovery,
and focus commands. Firmware receives only the versioned BLE payload described
by `TokenLinkDevice`; it does not receive provider credentials. A future local
firmware service can use `catalog.json` plus the generated
`dist/firmware/firmware-manifest.json` without coupling server logic to
PlatformIO build directories.

## Build and test C152

Install the pinned build tool in an ignored local environment:

```bash
python3.12 -m venv .venv-pio
.venv-pio/bin/python -m pip install platformio==6.1.19
bash scripts/test_firmware.sh
```

Create the same classes of assets published by a TokenLink release:

```bash
bash scripts/build_firmware_artifact.sh
```

This writes a merged image for offset `0x0`, a split-image archive, a
machine-readable manifest, and `SHA256SUMS` under `dist/firmware/`.

## Flash safety

The current image supports only M5Stack StopWatch Dev Kit C152. Build before
connecting to a serial target, identify the exact newly connected `/dev/cu.*`
port, and ask for explicit confirmation of that port immediately before an
upload. Never copy a port name from documentation.

```bash
bash scripts/pio.sh run -d firmware/stopwatch-c152 \
  -e m5stack-stopwatch --target upload \
  --upload-port /dev/cu.YOUR_CONFIRMED_C152_PORT

python3 firmware/stopwatch-c152/scripts/serial_probe.py \
  /dev/cu.YOUR_CONFIRMED_C152_PORT --seconds 30 \
  --expect CODEX_MICRO_STOPWATCH_READY
```

See M5Stack's official StopWatch factory-recovery guide before flashing:
<https://docs.m5stack.com/en/guide/restore_factory/stopwatch>.
