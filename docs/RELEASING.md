# Releasing TokenLink

TokenLink has three artifact classes. Keep their names and expectations
explicit:

- **Mac development artifact:** an ad-hoc-signed Universal 2 DMG for source/CI
  testing, not a notarized default download.
- **C152 firmware release:** a merged image, split-image archive, product/image
  manifests, and SHA-256 checksums built from `firmware/stopwatch-c152`.
- **Mac public release:** `TokenLink-<version>.dmg`, containing the Universal 2
  app and an Applications shortcut, Developer ID signed, Apple-notarized,
  stapled, checksummed, and attached to a versioned GitHub Release.

## Release gates

Before publishing a release:

1. Confirm `CHANGELOG.md`, both READMEs, version/build values in
   `packaging/Info.plist`, and the Latest News date agree.
2. Run `bash scripts/test.sh`, strict Swift formatting,
   `bash scripts/privacy_scan.sh`, and `bash scripts/resource_check.sh`.
3. If the release changes cost estimates, verify the bundled price-catalog
   version, effective date, first-party source URLs, model aliases, and all
   visible `Estimated/API-equivalent` labels.
4. Run `python scripts/test_package_firmware_release.py`,
   `bash scripts/test_firmware.sh`, and
   `bash scripts/build_firmware_artifact.sh`. Verify `dist/firmware/SHA256SUMS`.
   The version tag itself is the exact firmware source archive; no external
   checkout or separately maintained source ZIP is required.
5. For a hardware-facing release, flash the built candidate only after the exact
   C152 port is resolved and explicitly confirmed. Verify the serial boot marker,
   BLE v2 negotiation, a live sync, and user-visible interaction separately, then
   record the evidence under `docs/validation/`.
6. Push, review, tag, and publish only in the TokenLink repository. Never push a
   branch or open a PR in an external firmware repository as part of a TokenLink
   release.
7. Verify both arm64 and x86_64 slices in the mounted Mac DMG. Do not publish the
   architecture-neutral filename if either slice is missing.
8. Observe the hosted CI run on the final commit before tagging, then observe
   the tag-triggered Release workflow before publishing the final URL.

## Build a development artifact

```bash
bash scripts/build_release_artifact.sh
```

This creates `dist/TokenLink-<version>.dmg` and a matching `.dmg.sha256`. It
cross-compiles arm64 and x86_64, combines them into a Universal 2 executable,
adds an Applications shortcut, mounts the finished image, and checks both
architectures, Info.plist, SwiftPM resources, signature, and checksum.

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

The script notarizes and staples the app before creating the DMG, then signs,
notarizes, and staples the DMG itself. It exits if any public-release check
fails. Validate the checksum from the directory containing both downloads:

```bash
cd dist
shasum -a 256 -c TokenLink-<version>.dmg.sha256
```

## Configure GitHub release signing

The tag workflow requires these GitHub Actions secrets and fails closed if any
are missing:

| Secret | Content |
| --- | --- |
| `TOKENLINK_DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key (`.p12`) |
| `TOKENLINK_DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `TOKENLINK_CODESIGN_IDENTITY` | Full `Developer ID Application: ...` identity |
| `TOKENLINK_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect API private key (`.p8`) |
| `TOKENLINK_NOTARY_KEY_ID` | App Store Connect API key ID |
| `TOKENLINK_NOTARY_ISSUER_ID` | App Store Connect API issuer ID |

Never store the decoded certificate, private keys, or passwords in the
repository or release artifacts.

Pushing a `v*` tag runs `.github/workflows/release.yml`, imports the release
identity into an ephemeral keychain, rebuilds both artifact classes from that
tag, verifies their versions/checksums, and creates a GitHub Release from
`docs/releases/<version>.md`. A tag containing a hyphen is published as a
prerelease; a plain version tag such as `v0.2.2` is published as stable. The
firmware source is already in the tag. Do not add a source ZIP copied from
another repository.

Until Apple signing credentials are configured, ordinary CI may still create an
ad-hoc development DMG, but the tag workflow will refuse to publish it. Promote
a public DMG only after Gatekeeper verification on a separate Mac.
