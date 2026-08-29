# Changelog

Notable TokenLink changes are recorded here. The project follows semantic
versioning while it is pre-1.0; hardware verification is reported separately in
`docs/validation`.

## 0.2.0 — 2026-08-30

- Added Claude quota, multiple provider accounts, three UI languages, burn-rate
  projections, fair-pace markers, and macOS notifications.
- Added opt-in, on-device local token-counter summaries for documented Codex,
  Claude, and Kimi CLI transcript directories.
- Added negotiated StopWatch protocol v2 with byte-compatible v1 fallback,
  selected-provider rotation, three named work items, full active-task count,
  display settings, payload preview, and watch-to-Mac refresh/focus commands.
- Added the four-page Home, Quota, Sessions, and System companion experience;
  Home keeps the latest task/state on one row and balances its session/quota
  cards for the C152's circular display.
- Hardened Codex app-server proxy handling, provider host policies, diagnostics,
  Bluetooth deadlines, cancellation, and disconnect state.
- Made Kimi quota parsing tolerate unused-cycle responses that omit `used`,
  deriving it from `limit - remaining` instead.
- Made watch focus open the matching `codex://threads/<id>` task, with Codex app
  activation retained as a compatibility fallback.
- Fixed app packaging to include SwiftPM image resources, and added a versioned,
  checksummed release-artifact builder with archive verification.

## 0.1.0 — 2026-08-20

- Initial native macOS menu-bar app with Codex, Kimi, MiniMax, and GLM quota.
- Keychain-backed provider credentials, stale-data handling, diagnostics, and
  protocol-v1 Codex synchronization for M5Stack StopWatch.
