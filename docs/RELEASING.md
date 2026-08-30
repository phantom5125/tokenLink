# Releasing TokenLink

TokenLink has three artifact classes. Keep their names and expectations
explicit:

- **Mac development artifact:** ad-hoc signed and architecture-specific. It is
  for source/CI testing, not a notarized default download.
- **C152 firmware release:** a merged image, split-image archive, product/image
  manifests, and SHA-256 checksums built from `firmware/stopwatch-c152`.
- **Mac public release:** Developer ID signed, Apple-notarized, stapled,
  checksummed, and attached to a versioned GitHub Release.

## Release gates

Before publishing a release:

1. Confirm `CHANGELOG.md`, both READMEs, version/build values in
   `packaging/Info.plist`, and the Latest News date agree.
2. Run `bash scripts/test.sh`, strict Swift formatting, and
   `bash scripts/privacy_scan.sh`.
3. Run `python scripts/test_package_firmware_release.py`,
   `bash scripts/test_firmware.sh`, and
   `bash scripts/build_firmware_artifact.sh`. Verify `dist/firmware/SHA256SUMS`.
   The version tag itself is the exact firmware source archive; no external
   checkout or separately maintained source ZIP is required.
4. For a hardware-facing release, flash the built candidate only after the exact
   C152 port is resolved and explicitly confirmed. Verify the serial boot marker,
   BLE v2 negotiation, a live sync, and user-visible interaction separately, then
   record the evidence under `docs/validation/`.
5. Push, review, tag, and publish only in the TokenLink repository. Never push a
   branch or open a PR in an external firmware repository as part of a TokenLink
   release.
6. Build and test each advertised Mac architecture. Do not label an arm64-only
   archive as Intel-compatible.
7. Observe the hosted CI run on the final commit before tagging, then observe
   the tag-triggered Release workflow before publishing the final URL.

## Build a development artifact

```bash
bash scripts/build_release_artifact.sh
```

This creates `dist/TokenLink-<version>-macos-<architecture>.zip` and a matching
`.sha256`, then extracts the archive and checks the executable, Info.plist,
SwiftPM resources, signature, and checksum.

## Build C152 release artifacts

From a clean checkout, install the pinned build tool and run the repository
wrappers:

```bash
python3.12 -m venv .venv-pio
.venv-pio/bin/python -m pip install platformio==6.1.19
bash scripts/test_firmware.sh
bash scripts/build_firmware_artifact.sh
cd dist/firmware
shasum -a 256 -c SHA256SUMS
```

The generated merged `.bin` flashes at `0x0`. The `.zip` keeps the bootloader,
partition table, boot-app selector, application image, ELF, source partition
table, licenses, and image manifest together for installers and diagnostics.
`firmware-manifest.json` is the stable boundary for a future local firmware
server; it must not depend on a developer's PlatformIO cache path.

## Build a notarized public artifact

The maintainer needs an installed **Developer ID Application** certificate and a
notarytool keychain profile. Store the Apple notary credentials once, outside
the repository:

```bash
xcrun notarytool store-credentials tokenlink-notary
```

Then build, submit, staple, archive, and verify in one command:

```bash
TOKENLINK_CODESIGN_IDENTITY="Developer ID Application: YOUR TEAM" \
TOKENLINK_NOTARY_PROFILE="tokenlink-notary" \
bash scripts/build_release_artifact.sh
```

The script exits before producing a public artifact if notarization or stapling
fails. Validate the checksum from the directory containing both downloads:

```bash
cd dist
shasum -a 256 -c TokenLink-<version>-macos-<architecture>.zip.sha256
```

Pushing a `v*` tag runs `.github/workflows/release.yml`, rebuilds both artifact
classes from that tag, verifies their versions/checksums, and creates a GitHub
prerelease from `docs/releases/<version>.md`. The firmware source is already in
the tag. Do not add a source ZIP copied from another repository.

Until Apple signing credentials are configured, release notes must repeat that
the attached Mac archive is ad-hoc signed, not notarized, and limited to the
runner architecture. A Developer ID-signed, notarized artifact may be promoted
only after the public-release command above and Gatekeeper verification on a
separate Mac.
