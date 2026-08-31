# Releasing TokenLink

TokenLink has three artifact classes. Keep their names and expectations
explicit:

- **Mac community artifact:** an ad-hoc-signed Universal 2 DMG for source/CI
  testing and releases funded without an Apple Developer Program membership.
  Its release notes and Homebrew caveat must identify that it is not notarized.
- **C152 firmware release:** a merged image, split-image archive, product/image
  manifests, and SHA-256 checksums built from `firmware/stopwatch-c152`.
- **Mac notarized release:** `TokenLink-<version>.dmg`, containing the Universal
  2 app and an Applications shortcut, Developer ID signed, Apple-notarized,
  stapled, checksummed, and attached to a versioned GitHub Release. The release
  workflow selects this stronger identity automatically when all Apple secrets
  are configured.

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

## Configure optional GitHub release signing

The tag workflow uses these GitHub Actions secrets when the project has a paid
Apple Developer Program identity. Configure all six together or none of them;
a partial configuration fails closed:

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

Pushing a `v*` tag runs `.github/workflows/release.yml`, rebuilds both artifact
classes from that tag, verifies their versions/checksums, and creates a GitHub
Release from `docs/releases/<tag-without-v>.md`. A supported tag containing
`-alpha.N`, `-beta.N`, or `-rc.N` is published as a prerelease with an explicitly
ad-hoc-signed Mac development DMG. A plain version tag imports the release
identity into an ephemeral keychain when all six secrets exist. Without them,
the workflow publishes an explicitly labelled community build and adds the
same warning to its Homebrew cask. The firmware source is already in the tag.
Do not add a source ZIP copied from another repository.

## Publish through the Homebrew tap

Stable tags update `phantom5125/homebrew-tap` only after the GitHub Release and
its checksummed DMG exist. Bootstrap that public repository with a `main` branch
before the first stable release, then create a fine-grained GitHub token with
Contents read/write access limited to that repository. Store it in the TokenLink
repository as `HOMEBREW_TAP_TOKEN`.

The stable release workflow:

1. verifies access to the tap before creating the GitHub Release;
2. validates the DMG against its published SHA-256 file;
3. renders `Casks/tokenlink.rb` from `packaging/homebrew/tokenlink.rb.in`;
4. audits and installs the cask from an isolated local test tap; and
5. commits the exact version and SHA-256 to the public tap.

Users then install or upgrade with:

```bash
brew install --cask phantom5125/tap/tokenlink
brew upgrade --cask tokenlink
```

Community builds can be installed by the custom tap, but macOS can still require
the user to approve the first launch in **System Settings → Privacy & Security**.
Do not remove quarantine attributes in the cask. When donor funding makes an
Apple Developer Program membership available, configure the six Apple secrets;
the same workflow will emit a notarized cask without the community warning.
