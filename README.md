# TokenLink

**English** | [简体中文](README.zh-Hans.md)

[![CI](https://github.com/phantom5125/tokenLink/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/phantom5125/tokenLink/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img
    src="assets/readme/tokenlink-watch-v2-hero.png"
    alt="M5Stack StopWatch and macOS menu-bar quota panel"
    width="960">
</p>
<p align="center"><sub>Home · Quota · Sessions · System — live from your Mac to your wrist.</sub></p>
<!-- markdownlint-enable MD033 -->

TokenLink is a native macOS menu-bar control plane for coding-plan quota and an
M5Stack StopWatch companion. Version 0.2 shows Codex, Claude, Kimi, MiniMax,
and GLM in one local interface, adds a negotiated watch protocol v2, and keeps
the existing protocol-v1 firmware path byte-compatible.

> Status: early development. Provider APIs can change without notice. The exact
> v0.2 release candidate has been flashed to a C152 and exercised end to end with
> the installed Mac app, including protocol-v2 negotiation, aggregate active count,
> and three-provider sync. Physical touch/layout sign-off and long-duration power
> behavior remain follow-up validation.

TokenLink is an independent open-source project and is not affiliated with,
endorsed by, or an official product of OpenAI, Moonshot AI, MiniMax, Zhipu AI,
or M5Stack. Provider names and trademarks belong to their respective owners.

## Latest News

- **2026-08-30 — The exact release candidate passed its first C152 end-to-end
  run.** Firmware commit [`0d5bf6c`](https://github.com/phantom5125/codex-micro-stopwatch/commit/0d5bf6c)
  booted after a hash-verified flash; TokenLink 0.2.0 negotiated v2 and sent live
  Codex, Kimi, and MiniMax payloads with the full active count.
- **2026-08-30 — Home now reflects the real Codex workload.** The newest task and
  its state share one compact row, while Active counts every running or
  needs-input Codex task — not only the three items sent for display.
- **2026-08-30 — Watch Face v2 reached release-candidate form.** A round-safe
  four-page interface covers Home, Quota, Sessions, and System, with matching
  provider icons and quota bars on the watch and Mac.
- **2026-08-29 — Watch and Mac became one interaction surface.** Tapping the Home
  task opens Sessions; tapping a Codex session opens its matching
  `codex://threads/<id>` task on the Mac.
- **2026-08-22 — Protocol v2 was defined.** Multi-provider quota, named work
  items, watch-to-Mac refresh/focus commands, and settings were added without
  breaking the existing v1 payload.

## What it does

- Native `MenuBarExtra` plus a four-route Control Center: Overview, Providers,
  StopWatch, and Settings & Diagnostics.
- Normalizes several quota windows without inventing plan limits.
- Projects burn rate per window ("runs out in ~3h at this pace") from recent
  local samples — no extra API calls.
- Optionally draws a fair-pace marker showing where a window would be under
  even consumption.
- Offers an opt-in beta scan of documented local Codex, Claude, and Kimi CLI
  transcript directories to summarize recent token counters on-device.
- Sends macOS notifications when a window runs low, a window resets, or a
  stored credential is rejected (toggle in Settings).
- Keeps last-known-good snapshots and marks them stale when refresh fails.
- Stores explicit API keys in macOS Keychain under service
  `io.github.phantom5125.tokenlink.provider` and stable provider accounts.
- Binds a single StopWatch by CoreBluetooth identifier and writes with response.
- Negotiates watch protocol v2 and sends every selected provider in one sync; v1
  firmware continues to receive only the unchanged Codex primary-window payload.
- Tracks up to three named Codex work items and accepts v2 refresh/focus commands.
  Focus opens the matching `codex://threads/<id>` task link, with app activation
  as a compatibility fallback.
- Configures v2 theme, wake behavior, hour format, provider selection, and shows
  the last payload sent from the StopWatch page.
- Exports diagnostics only after redacting secrets, user paths, account labels,
  and device identifiers.

## Quick Start

### Without an M5Stack StopWatch

This is the complete path for trying the macOS menu-bar experience. It needs
macOS 14+ and Xcode 26+ or a Swift 6.2+ toolchain:

```bash
git clone https://github.com/phantom5125/tokenLink.git
cd tokenLink
bash scripts/package_app.sh
open TokenLink.app
```

Open **Control Center → Providers**, enable Codex, and refresh. TokenLink reuses
the local Codex CLI login; no Codex API key is stored. Other providers can be
enabled independently.

The package script includes SwiftPM resources, creates a release-mode app,
applies an ad-hoc signature by default, and verifies the resulting bundle. A CI
development artifact is also produced for each revision. The v0.2.0 RC download
is Apple-Silicon-only and ad-hoc signed, so building from source remains the
supported first-run path until a Developer ID-signed, notarized release exists.

### With an M5Stack StopWatch C152

1. Complete the Mac-only steps above.
2. Download `TokenLink-StopWatch-C152-0.2.0-rc.1.bin` and its `.sha256` from the
   [v0.2.0-rc.1 release](https://github.com/phantom5125/tokenLink/releases/tag/v0.2.0-rc.1),
   or build the exact verified firmware source at
   [`0d5bf6c`](https://github.com/phantom5125/codex-micro-stopwatch/tree/0d5bf6c).
   The upstream review is tracked in
   [`digitsisyph/codex-micro-stopwatch#5`](https://github.com/digitsisyph/codex-micro-stopwatch/pull/5).
   Verify the checksum, resolve and confirm the exact Espressif serial port, then
   flash the C152-only merged image at offset `0x0`. The companion repository has
   the source-build procedure; M5Stack documents the
   [factory-recovery path](https://docs.m5stack.com/en/guide/restore_factory/stopwatch).
3. In TokenLink, open **Control Center → StopWatch**, scan, select the exact
   device, bind it, and press **Sync watch now**.

Do not flash the C152 image to another M5Stack model, and do not expect the
four-page UI from protocol-v1 firmware. The RC image is a development artifact;
the upstream firmware PR and physical touch/power sign-off are still pending.

### Verify a source checkout

```bash
swift build
bash scripts/test.sh
bash scripts/build_release_artifact.sh
```

The last command writes a versioned `.zip` and SHA-256 checksum under `dist/`
and verifies that the archive still contains its executable, Info.plist,
resource bundle, and valid signature. Maintainer signing, notarization, and
publication steps are documented in [`docs/RELEASING.md`](docs/RELEASING.md).

## Requirements

- macOS 14 or newer
- Apple Silicon or Intel Mac with Xcode 26+ / Swift 6.2+ (Command Line Tools can
  build the app; the included test wrapper handles CLT installations whose
  Swift Testing search paths are incomplete)
- A working `codex` CLI for Codex quota
- Optional M5Stack StopWatch C152 running matching protocol-v2 firmware

## Provider setup

Open **Control Center → Providers**. Secret fields are always blank: TokenLink
shows only whether a credential is configured — plus a masked head/tail hint of
the stored key (for example `sk-cp-ab…wxyz`) and its source (Keychain, CLI, or
environment variable) — and never reads a key back into the UI. Each provider
section links to the official console where you can create a key.

Credentials resolve in this order: an explicit key in Keychain, then the
provider's documented local CLI credential (Kimi and Claude), then a small
allowlist of environment variables (`KIMI_CODE_API_KEY`/`KIMI_API_KEY`,
`MINIMAX_API_KEY`, `ZAI_API_KEY`/`ZHIPU_API_KEY`/`GLM_API_KEY`/`BIGMODEL_API_KEY`,
`CLAUDE_CODE_OAUTH_TOKEN`). The environment fallback exists mainly for testing.

Multiple accounts per provider are supported as an advanced, not-recommended
option: use **Add account (advanced)** in a provider section to attach another
plan with its own label and key. Codex and Claude stay single-account because
they use the local CLI sign-in.

The app UI is available in English, 中文（简体）, and 日本語; choose under
**Settings & Diagnostics → Language** or follow the system language.

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

### Claude

TokenLink reads the OAuth usage endpoint used by Claude Code's own `/usage`
display, reusing the Claude Code CLI's local sign-in (its Keychain credential
item, read-only; expired tokens are ignored and the refresh token is never
read). Anthropic pay-as-you-go API keys do not report subscription quota, so
there is intentionally no key field for Claude.

### MiniMax

Store a MiniMax Coding Plan API key and choose Global or China. Requests are
restricted to the selected official host (`www.minimax.io` or `www.minimaxi.com`)
and use the Token Plan remains endpoint.

### GLM

Store a GLM Coding Plan API key and choose Global (Z.AI) or China (BigModel).
TokenLink supports the current numeric-unit/camelCase quota shape plus an explicit
legacy compatibility branch. It preserves returned windows and does not estimate
limits from a plan name.

Provider and Codex-path changes are persisted immediately and take effect
after restarting the app. Region, account, and refresh-interval changes take
effect immediately.

## StopWatch binding and protocol v1/v2

1. Keep the matching StopWatch firmware running and Bluetooth enabled.
2. Open **Control Center → StopWatch** and press **Scan**.
3. Select one discovered identifier and bind it.
4. Press **Sync watch now**.

Discovery occurs only on explicit request. TokenLink first checks connected quota
and HID peripherals, then performs a short broad scan filtered by the StopWatch
name or private service UUID. It does not connect until you explicitly bind an
identifier. Once bound, fresh selected-provider snapshots sync automatically;
**Sync watch now** remains available as a manual action. Connect, capability-read,
and write operations have finite deadlines, and quota writes require an ATT
response.

The v1 firmware understands only this payload:

```json
{"remaining_percent":72,"reset_in_seconds":900}
```

Protocol v1 always sends only Codex's primary window. Kimi, Claude, MiniMax, and
GLM are never mislabeled as Codex on an existing v1 watch face.

Protocol v2 is negotiated through an optional read-only capabilities
characteristic. A compatible device can receive up to three quota windows, up
to three short named work items, selected-provider rotation, and watch settings.
If capability discovery, reading, or decoding fails, TokenLink silently falls
back to v1. The Mac implementation and fake-transport tests are complete, and
the exact release candidate has carried its full active-count field and live
multi-provider payloads to a C152. Physical layout/touch review and long-duration
power behavior remain explicitly separate validation layers. See the latest report in
[`docs/validation`](docs/validation/).

## Privacy and security

- Explicit API keys: macOS Keychain only.
- Non-secret configuration: `~/Library/Application Support/TokenLink/config.json`
  with user-only permissions.
- No browser-cookie access, Full Disk Access, analytics, or remote TokenLink
  service.
- The optional local-usage beta reads only `.codex/sessions`, `.claude/projects`,
  and `.kimi-code/sessions`; it extracts token counters locally and never sends
  transcript data over the network.
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
  ├─ TokenLinkProviders  Codex/Claude/Kimi/MiniMax/GLM adapters and host policy
  └─ TokenLinkDevice     v1/v2 projection, negotiation, commands, CoreBluetooth
```

Each provider owns a fixture-tested parser and emits a shared `QuotaSnapshot`.
The app is the only UI state owner. The device layer receives deliberate v1 or
v2 projections and never receives provider credentials.

## Protocol-v2 status

The Mac side implements payload projection, capability negotiation, v1 fallback,
provider rotation, three visible work-item slots, a full active-task count,
settings, payload preview, and a watch-to-Mac command channel. The companion
firmware work — four watch pages, touch focus commands, optional pet theme, and
raise-to-wake — lives in the separate `codex-micro-stopwatch` project. The exact
release candidate now has a verified C152 flash, boot, protocol-v2 exchange, and
multi-provider sync; physical layout/touch review and the 24-hour power soak are
not yet signed off.

## Contributing

Contributions and well-formed ideas are welcome. Small fixes may be submitted
directly; large UI, protocol, provider, or hardware changes should begin with an
issue proposal. See [CONTRIBUTING.md](CONTRIBUTING.md), the
[Code of Conduct](CODE_OF_CONDUCT.md), and the existing issue templates.

## License and acknowledgements

TokenLink is licensed under the [Apache License 2.0](LICENSE). Required
attributions and development acknowledgements are in [NOTICE](NOTICE), and
brand-use boundaries are in [TRADEMARKS.md](TRADEMARKS.md).
