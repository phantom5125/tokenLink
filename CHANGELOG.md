# Changelog

Notable TokenLink changes are recorded here. The project follows semantic
versioning while it is pre-1.0; hardware verification is reported separately in
`docs/validation`.

## 0.2.2 — Unreleased

- Keep watch-to-Mac focus commands within the 20-byte default ATT payload so
  they are delivered even when the C152 also has a low-MTU HID connection.
  TokenLink accepts both the compact on-device frame and the earlier verbose
  protocol-v2 command format.
- Recreate the watch-command listener whenever a StopWatch is rebound, and log
  redacted command receipt before resolving its slot to a Codex task.

- Added a credential-free StopWatch checklist for Bluetooth authorization,
  adapter readiness, device binding, connection progress, protocol-v2 C04
  command notifications, and last successful sync.
- Added actionable recovery guidance for denied permission, stale app-identity
  bindings, connection timeouts, and missing command notifications.
- Included the same redacted Bluetooth state-machine fields in diagnostics
  exports without device UUIDs, credentials, token values, or payload bodies.

- Target Codex Desktop's installed application bundle when opening a
  `codex://threads/<id>` task link instead of treating generic LaunchServices
  scheme acceptance as proof that Codex received it.
- Added a per-task Mac-side focus test and a visible last-outcome status so BLE
  command delivery can be distinguished from app-link delivery.
- Preserve the app-activation fallback while reporting it as a partial result,
  rather than implying that the matching task was focused.

- Page through the complete Codex `thread/list` result in updated-activity
  order, deduplicate moving threads across pages, and fail closed instead of
  presenting a bounded partial result as the full active-session count. Remove
  sessions that disappear after a complete successful refresh.
- Keep three glanceable watch slots while prioritizing needs-input, failed,
  running, completed, and unknown sessions in that order; unaffected sessions
  retain their slot when a more useful item arrives.
- Give every Sessions state a distinct color, shape, text label, and motion
  policy: blue running orbit, amber needs-input pulse, static green completion
  check, and static red failure alert.
- Refresh Codex session lifecycle independently every ten seconds and consult
  the local rollout lifecycle before treating Desktop-owned tasks as terminal.
  Ambiguous tasks stay neutral `UNKNOWN`; only explicit completion evidence
  gets a green `DONE` check.
- Keep execution state separate from acknowledgement. Opening a pending task
  changes its amber attention pulse from `ACTION` to a static `OPENED` ring;
  it does not mark the task complete, and a newer provider event makes it
  actionable again.
- Show both the aggregate active count and visible row count on Sessions, while
  keeping protocol v2 and the three-slot focus contract unchanged.

## 0.2.1 — 2026-08-30

- Moved the exact default wireless M5Stack StopWatch C152 firmware source into
  `firmware/stopwatch-c152`, retaining its MIT and Space Mono OFL notices.
- Added a repository-local, pinned PlatformIO build; ten native firmware tests;
  an explicit 16 MB partition table; and CI coverage independent of any external
  firmware checkout.
- Added deterministic C152 release packaging: a merged image, a split-image
  archive, firmware/server manifests, and SHA-256 checksums.
- Added one-tag release automation for both the macOS development artifact and
  C152 assets. The Mac archive remains ad-hoc signed until Developer ID signing
  and notarization are configured.
- Made the protocol-v2 four-page watch face the boot default; the legacy
  dashboard now appears only after a successfully parsed v1 payload.
- Made Claude Code credential access explicitly opt-in, explained the macOS
  Keychain authorization scope before prompting, and replaced automatic legacy
  TokenLink key reads with a separately confirmed one-time migration.
- Added an explicit one-time StopWatch rebind for the `app.tokenlink` Bluetooth
  identity and made protocol v2 wait for confirmed C04 notification subscription
  before reporting the connection ready, preventing silent session-focus failures.
- Documented a single-repository Quick Start for Mac-only users, C152 builders,
  and future protocol-compatible firmware targets.

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
