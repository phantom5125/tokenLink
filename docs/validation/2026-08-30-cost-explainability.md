# Cost explainability validation — 2026-08-30

This report covers `codex/v0.3.1-cost-explainability` on the integrated v0.3.0
Costs beta.

| Check | Evidence | Status |
| --- | --- | --- |
| Build | `swift build` completes with the new SwiftUI disclosure. | PASS |
| Automated tests | `bash scripts/test.sh --quiet` passes 234 tests. | PASS |
| Category reconciliation | Tests verify uncached input, cache read, cache write, and output category amounts sum to the model subtotal. | PASS |
| Long-context accuracy | Tests verify request-level multipliers and the derived effective rates without multiplying a period aggregate. | PASS |
| Provenance | The canonical catalog entry and reviewed HTTPS source survive local aggregation and are visible next to catalog version/effective date. | PASS |
| Exclusions | Unknown model IDs remain absent from totals and are listed only in the local Costs UI. | PASS |
| Diagnostics boundary | Existing diagnostics export only source status/freshness/catalog version, never model IDs, token details, source URLs, or monetary values. | PASS |
| Resource gate | Production workload: 10.31 seconds, 84,525,056-byte maximum RSS, and 6,044,344-byte release executable. | PASS |

Physical UI acceptance should expand cards with zero, one, and several priced
models in all three languages and confirm long model IDs wrap acceptably.
