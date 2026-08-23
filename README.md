# TokenLink

<p align="center">
  <img src="assets/branding/banner-hero.png" alt="TokenLink banner" width="720">
</p>

TokenLink is a native macOS menu-bar control plane that shows your AI coding
plan quota — Codex, Kimi, MiniMax, and GLM — in one place, and syncs the Codex
primary window to the M5Stack StopWatch over Bluetooth (GATT protocol v1).

**Your AI quota, at a glance.**

## Features

- Menu-bar gauge with the most constrained quota window across providers.
- Control-center window: Overview, Providers, StopWatch, Settings & Diagnostics.
- Four independent provider adapters with per-provider HTTPS host allowlists.
- API keys live in the macOS Keychain; config JSON never contains secrets.
- StopWatch sync: only the Codex primary window is projected to the legacy
  watch payload — other providers are never mislabeled as Codex.
- Last-known-good caching with honest stale/error display.
- Redacted diagnostics export.

## Requirements

- macOS 14 or newer.
- Swift 6.2 toolchain or newer (Xcode for full packaging and UI automation).
- M5Stack StopWatch Dev Kit (C152) for watch sync.

## Build & run

```bash
swift build
swift test        # full Xcode required for the test runner
swift run tokenlink
```

Package a signed `.app`:

```bash
bash scripts/package_app.sh   # builds TokenLink.app and ad-hoc signs it
open TokenLink.app
```

## Provider setup

Open **Control Center → Providers**. Keys are stored in Keychain and are never
prefilled back into text fields.

| Provider | Credential |
| --- | --- |
| Codex | Reads the local `codex` CLI app server; no key needed. |
| Kimi | Coding Plan API key, or read-only reuse of the Kimi Code CLI login. |
| MiniMax | Coding Plan API key; choose Global or China region in Settings. |
| GLM | Coding Plan API key; Global (`api.z.ai`) or China (`open.bigmodel.cn`). |

## StopWatch binding

1. Open **Control Center → StopWatch → Discover…** to start an explicit
   discovery session.
2. Select your device from the list — binding requires a selection.
3. Use **Sync Codex now** to push the current Codex primary quota.

Protocol v1 sends only `remaining_percent` and `reset_in_seconds` for the
Codex primary window. Protocol v2 (multiple windows, provider IDs, watch-face
rotation) is a separate upcoming project.

## Privacy

TokenLink runs fully on-device: no local web server, no daemon, no browser
cookies, no Full Disk Access. See `SECURITY.md` for secret handling and
`scripts/privacy_scan.sh` for the CI-enforced privacy rules.

## Troubleshooting

- **Missing credential**: the provider row shows "Not configured" — add the key
  in Providers, or sign in with the Kimi Code CLI for Kimi.
- **Stale data**: rows show the original fetch time in orange; hit Refresh.
- **Codex not found**: set a custom `codex` path in `config.json`.

## Uninstall

Quit from the menu bar, remove `TokenLink.app`, then delete
`~/Library/Application Support/TokenLink` and the Keychain entries under
`io.github.phantom5125.tokenlink.provider`.

## License

MIT — see `LICENSE`. Third-party acknowledgements in `NOTICE.md`.
