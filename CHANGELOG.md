# Changelog

Notable TokenLink changes are recorded here. The project follows semantic
versioning while it is pre-1.0; hardware verification is reported separately in
`docs/validation`.

## Unreleased

- Added project-owned Homebrew Cask distribution for stable releases. The tag
  workflow verifies tap access before publication, renders the exact release
  SHA-256, audits and installs the cask, and commits it to
  `phantom5125/homebrew-tap` only after the GitHub Release exists.
- Made Apple Developer ID signing an optional stronger release identity: all
  six credentials still fail closed when partially configured, while an
  unfunded community release is explicitly labelled ad-hoc/non-notarized in
  both GitHub release notes and its Homebrew caveat.

## 0.3.0-rc.2 — 2026-08-31

- Made `assets/branding/logo-mark-light.png` the single source of truth for the
  Finder, menu-bar, menu-panel, notification, and packaged App icons; removed
  the separately drawn heavy-stroke icon renderer and regenerate ICNS during
  every release build.
- Fixed installed-app startup by resolving SwiftPM resources from the standard
  `Contents/Resources` app location before `Bundle.module`; mounted-DMG release
  validation now cold-starts the distributed executable and fails on resource-
  bundle crashes or branding drift.
- Decoupled C04 watch-command notification setup from C02 quota readiness, so a
  new Mac can initiate pairing and deliver quota even while optional Session
  focus/refresh notifications are still being enabled.
- Advanced the C152 GATT migration revision to clear pre-RC2 bonds exactly once,
  allowing a prepared or previously tested watch to pair cleanly with its new
  host after installing the matching firmware.

## 0.3.0-rc.1 — 2026-08-31

- Expanded the Mac Cost Center into a local Usage & Cost workspace with
  Overview, Trends, Attribution, and Costs sections.
- Added project, model, reasoning-effort, and privacy-safe Session attribution
  across locally recorded Codex, Claude, and Kimi token usage.
- Added a GitHub-style activity calendar, metric-switchable Token/cost/active-
  time views, hourly distribution, and an immediately preceding equal-length
  period comparison aligned by local calendar day.
- Added custom date ranges and a documented active-time estimate based on
  per-Session activity gaps of up to five minutes, including explicit overlap
  and isolated-event caveats.
- Added a local incremental history store with changed-file reparsing, unchanged-
  file reuse, a 400-day/250,000-event bound, atomic owner-only persistence, and
  no prompt, response, tool-output, full-path, or raw Session-ID retention.
- Added API-equivalent pricing coverage directly to the dashboard so unpriced
  usage cannot be mistaken for zero-cost usage.

## 0.2.3-rc.1 — 2026-08-31

- Reworked the Data watch face around a TokenLink-style open quota arc, with
  rounded Nunito numerals, a time-proportional plan tick, percentage-point
  variance, reset countdown, and a compact session-action pill.
- Rebuilt the macOS app icon as high-contrast vector geometry so the surrounding
  open arc remains visible at 16 px Finder and sidebar sizes.
- Added an optional protocol-v2 window-duration hint for fair-pace rendering,
  preserving compatibility in both directions and omitting pace for unknown
  windows instead of inventing plan limits.
- Promoted the Mac Costs beta to a dedicated localized Cost Center route with
  Today / Week / Month views and drill-down cost provenance.
- Aligned Codex API-equivalent estimates with the leading community method:
  request-level deltas, disjoint input/cache buckets, recorded and configured
  Fast tiers, request-level long-context pricing, current GPT-5.6 official
  rates, and streaming support for normal rollout files up to 256 MiB.

- Added a persisted Today / Week / Month selector shared by the Costs screen
  and local-estimate menu-bar supplement.
- Built all three local estimate windows from one bounded transcript pass and
  cached them independently, so changing the visible period performs no new
  file reads.
- Matched authoritative daily, weekly, and monthly spend to the same selected
  period while keeping provider balances visible and separate.

- Added an opt-in Costs beta that keeps provider-reported OpenRouter and
  DeepSeek balances separate from coding-plan quota.
- Added seven-day local `Estimated/API-equivalent` cost estimates for Codex,
  Claude, and Kimi, backed by a versioned, reviewed price catalog.
- Added bounded streaming transcript scans, explicit cost provenance and
  freshness, and CI gates for privacy, memory, runtime, and executable size.

## 0.2.2 — Unreleased

- Added a Universal 2 `TokenLink-0.2.2.dmg` with a drag-to-Applications layout,
  mounted-image verification, checksums, and a tag workflow that refuses to
  publish without Developer ID signing and Apple notarization credentials.
- Added the TokenLink dashboard-and-link mark to the macOS app, menu bar, and
  menu panel, with an adaptive monochrome status-item variant.
- Keep local app bundles under the hidden SwiftPM build directory so macOS
  LaunchServices cannot rediscover worktree artifacts as a second TokenLink.
- Give every full C152 installation a new persistent random-static BLE identity
  so a firmware flash cannot reconnect with stale macOS bond keys. Binding a
  selected watch now immediately connects and proves the new identity.
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
  gets a green `DONE` check. Scan recent rollouts backward by chunks so a
  long-running task remains running after more than 256 KB of tool output.
- Keep execution state separate from acknowledgement. Opening a pending task
  changes its amber attention pulse from `ACTION` to a static `OPENED` ring;
  it does not mark the task complete, and a newer provider event makes it
  actionable again.
- Show both the aggregate active count and visible row count on Sessions, while
  keeping protocol v2 and the three-slot focus contract unchanged.
- Merge M5Unified's latched PM1 click event with direct power-button sampling,
  so a short red-button click reliably wakes desk sleep even when the full
  press falls between two samples. Live press tracking still owns held and
  double-click gestures, preventing duplicate actions.

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
