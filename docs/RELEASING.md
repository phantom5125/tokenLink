# Releasing TokenLink

TokenLink has two different artifact classes. Keep their names and expectations
explicit:

- **Development artifact:** ad-hoc signed, architecture-specific, produced by CI
  and source checkouts. It is for testing, not the default public download.
- **Public release:** Developer ID signed, Apple-notarized, stapled, checksummed,
  and attached to a versioned GitHub Release.

## Release gates

Before publishing a release:

1. Confirm `CHANGELOG.md`, both READMEs, version/build values in
   `packaging/Info.plist`, and the Latest News date agree.
2. Run `bash scripts/test.sh`, strict Swift formatting, and
   `bash scripts/privacy_scan.sh`.
3. For a hardware-facing release, merge and tag the matching
   `codex-micro-stopwatch` firmware. Flash that exact candidate only after the
   C152 port is resolved and confirmed, then record the observed result under
   `docs/validation/`.
4. Build and test each advertised Mac architecture. Do not label an arm64-only
   archive as Intel-compatible.
5. Observe the hosted CI run on the final commit.

## Build a development artifact

```bash
bash scripts/build_release_artifact.sh
```

This creates `dist/TokenLink-<version>-macos-<architecture>.zip` and a matching
`.sha256`, then extracts the archive and checks the executable, Info.plist,
SwiftPM resources, signature, and checksum.

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

Create the GitHub Release from the version tag and attach both the `.zip` and
`.sha256`. Release notes must link the exact compatible firmware tag and repeat
any remaining hardware or architecture limitations.
