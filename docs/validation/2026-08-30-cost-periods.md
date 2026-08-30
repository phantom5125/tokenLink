# Cost-period switching validation — 2026-08-30

This report covers the independent `codex/v0.3.1-cost-periods` development
branch based on the integrated v0.3.0 Costs beta.

| Check | Evidence | Status |
| --- | --- | --- |
| Build | `swift build` completes for the macOS app. | PASS |
| Automated tests | `bash scripts/test.sh --quiet` passes 237 tests. | PASS |
| Period semantics | Tests pin Today to the local day boundary and Week / Month to trailing 7 / 30 calendar days. | PASS |
| No rescan on switch | A dashboard regression loads all periods once, switches Week → Today → Month, verifies distinct values, and retains one loader call. | PASS |
| Local scan bound | One observer pass begins at the Month boundary; each deduplicated record is priced once and accumulated only into matching periods. | PASS |
| Persistence | New and migrated configuration default to Week; an explicit selection round-trips. | PASS |
| Resource gate | Production workload: 10.36 seconds, 84,705,280-byte maximum RSS, and 6,045,368-byte release executable. | PASS |

Physical UI acceptance should confirm the capsule sizing and menu-bar text in
English, Simplified Chinese, and Japanese. This branch does not alter
credentials, network requests, quota refresh, Bluetooth, or the StopWatch
payload.
