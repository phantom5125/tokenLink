# TokenLink

TokenLink is a native macOS menu-bar control plane for coding-plan quota and an
M5Stack StopWatch companion. Version 0.1 shows Codex, Kimi, MiniMax, and GLM in
one local interface while preserving compatibility with the existing
`codex-micro-stopwatch` firmware.

> Status: early development. Provider APIs can change without notice. The Mac
> application is implemented and testable; physical-device validation is tracked
> separately from automated compatibility tests.

TokenLink is an independent open-source project and is not affiliated with,
endorsed by, or an official product of OpenAI, Moonshot AI, MiniMax, Zhipu AI,
or M5Stack. Provider names and trademarks belong to their respective owners.

## What it does

- Native `MenuBarExtra` plus a four-route Control Center: Overview, Providers,
  StopWatch, and Settings & Diagnostics.
- Normalizes several quota windows without inventing plan limits.
- Keeps last-known-good snapshots and marks them stale when refresh fails.
- Stores explicit API keys in macOS Keychain under service
  `io.github.phantom5125.tokenlink.provider` and stable provider accounts.
- Binds a single StopWatch by CoreBluetooth identifier and writes with response.
- Automatically syncs a bound watch after a fresh Codex snapshot, with bounded
  timeout/retry behavior and disconnect-state tracking.
- Exports diagnostics only after redacting secrets, user paths, account labels,
  and device identifiers.

## Requirements

- macOS 14 or newer
- Apple Silicon or Intel Mac with Xcode 16+ (Command Line Tools can build the app;
  the included test wrapper handles CLT installations whose Swift Testing search
  paths are incomplete)
- A working `codex` CLI for Codex quota
- Optional M5Stack StopWatch running the current `codex-micro-stopwatch` firmware

## Build and run

```bash
git clone https://github.com/phantom5125/tokenLink.git
cd tokenLink
swift build
bash scripts/test.sh
bash scripts/package_app.sh
open TokenLink.app
```

The package script builds release mode, creates `TokenLink.app`, applies an ad-hoc
signature, and verifies the bundle. Move the app to `/Applications` for regular
use. A notarized release pipeline is intentionally outside v0.1.

## Provider setup

Open **Control Center → Providers**. Secret fields are always blank: TokenLink
shows only whether a credential is configured and never reads a key back into the
UI.

### Codex

TokenLink starts the local command `codex app-server --listen stdio://`, performs
the JSON-RPC initialization handshake, and reads `account/rateLimits/read`. It
reuses the Codex CLI's own login state; TokenLink does not store a Codex API key.
If `codex` is not on the app's `PATH`, set an explicit executable path.

### Kimi

You can store a Kimi Coding API key in Keychain. If no explicit key exists,
TokenLink can read the current, non-expired access token from
`~/.kimi-code/credentials/kimi-code.json`. It reads no sibling files, browser
cookies, or refresh token, and it never refreshes or writes the CLI credential.

### MiniMax

Store a MiniMax Coding Plan API key and choose Global or China. Requests are
restricted to the selected official host (`www.minimax.io` or `www.minimaxi.com`)
and use the Token Plan remains endpoint.

### GLM

Store a GLM Coding Plan API key and choose Global (Z.AI) or China (BigModel).
TokenLink supports the current numeric-unit/camelCase quota shape plus an explicit
legacy compatibility branch. It preserves returned windows and does not estimate
limits from a plan name.

Provider, region, and Codex-path changes are persisted immediately and take effect
after restarting the v0.1 app. Refresh interval changes take effect immediately.

## StopWatch binding and protocol v1

1. Keep the existing StopWatch firmware running and Bluetooth enabled.
2. Open **Control Center → StopWatch** and press **Scan**.
3. Select one discovered identifier and bind it.
4. Press **Sync Codex now**.

Discovery occurs only on explicit request. TokenLink first checks connected quota
and HID peripherals, then performs a short broad scan filtered by the StopWatch
name or private service UUID. It does not connect until you explicitly bind an
identifier. Once bound, fresh Codex refreshes sync automatically; **Sync Codex
now** remains available as a manual action. Connect and write operations have
finite deadlines and use a write-with-response operation.

The v1 firmware understands only this payload:

```json
{"remaining_percent":72,"reset_in_seconds":900}
```

For accuracy, v0.1 sends only Codex's primary window. Kimi, MiniMax, and GLM are
shown on the Mac but are never mislabeled as Codex on the current watch face.

## Privacy and security

- Explicit API keys: macOS Keychain only.
- Non-secret configuration: `~/Library/Application Support/TokenLink/config.json`
  with user-only permissions.
- No browser-cookie access, Full Disk Access, analytics, or remote TokenLink
  service.
- Provider URLs are HTTPS and checked against narrow official-host allowlists
  before credential-bearing requests.
- Diagnostics are redacted before they are written to a user-selected file.

See [SECURITY.md](SECURITY.md) for reporting and threat-boundary details.

## Troubleshooting

- **Codex unavailable:** run `codex --version`, confirm the CLI is signed in, and
  set its path in Providers if the menu-bar app has a smaller `PATH`.
- **Credential needed:** replace the provider key in Providers. The old value is
  intentionally never displayed.
- **Stale quota:** TokenLink keeps the last successful snapshot and labels it
  stale; use Refresh after network access returns.
- **No StopWatch discovered:** confirm the firmware exposes the private quota
  GATT service or the `Codex Micro` device name, grant Bluetooth access when macOS
  asks, and scan again.
- **Launch at login requires approval:** enable TokenLink in System Settings →
  General → Login Items.

## Uninstall

Quit TokenLink and remove `TokenLink.app`. Optionally remove its configuration:

```bash
rm -rf "$HOME/Library/Application Support/TokenLink"
```

Keychain items can be removed from Keychain Access, or individually with the
`security` command using service `io.github.phantom5125.tokenlink.provider` and
accounts `kimi`, `minimax`, or `glm`.

## Architecture

```text
TokenLinkApp        SwiftUI/AppKit state, settings, Keychain, diagnostics
  ├─ TokenLinkCore       provider-neutral quota and refresh state
  ├─ TokenLinkProviders  Codex/Kimi/MiniMax/GLM adapters and host policy
  └─ TokenLinkDevice     v1 projection, binding, and CoreBluetooth transport
```

Each provider owns a fixture-tested parser and emits a shared `QuotaSnapshot`.
The app is the only UI state owner. The device layer receives a deliberate legacy
projection instead of provider-specific data.

## Protocol-v2 roadmap

The next firmware phase will be additive and versioned: multi-provider rotation,
Mac-configured provider/logo profiles, fewer and more memorable conversation
slots, and a useful right-button action. Protocol v1 compatibility remains a
separate path so existing watches continue to work during migration.

## License

MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
