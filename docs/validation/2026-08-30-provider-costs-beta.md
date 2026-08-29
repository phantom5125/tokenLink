# Provider Costs Beta Merge Readiness — 2026-08-30

This report covers the opt-in provider-costs beta after rebasing its twelve
feature commits onto `origin/main` at `51b0aec`. Quota remains the primary
domain; authoritative balances and local API-equivalent estimates are reviewed
as separate beta capabilities.

## Results

| Layer | Evidence | Status | Limitations |
| --- | --- | --- | --- |
| Rebase integrity | `git range-diff` preserved all twelve Costs commits. The only intentional changes adopt the `main` Codex executable resolver and compose the resource job with the current packaging workflow. | PASS | Rewritten commit IDs require updating the remote feature branch with force-with-lease. |
| Build | `swift build` completed on the rebased tree. | PASS | Local build target is Apple Silicon macOS. |
| Automated tests | `bash scripts/test.sh` completed 227 tests covering quota isolation, authoritative adapters, local estimation, TTL, streaming bounds, cancellation, overflow, privacy, and v1/v2 behavior. | PASS | Provider HTTP tests use synthetic fixtures and injected transports; they do not spend from or expose a live account. |
| Main compatibility | The v0.2 provider-logo test exposed missing cost-only brand assets. Quota providers still require bundled logos; OpenRouter and DeepSeek now explicitly use the existing code-native symbol fallback until redistributable brand assets are reviewed. | PASS | The fallback is intentional, not an official provider logo. |
| Swift format | Strict lint passed for `Package.swift`, `Sources`, and `Tests`. | PASS | None. |
| Privacy scan | `bash scripts/privacy_scan.sh` passed. | PASS | Static scanning complements tests; it cannot recognize every future secret format. |
| Resource gate | The production 64 MiB workload completed in 9.48 seconds with 84,393,984 bytes maximum RSS; the release executable was 5,717,768 bytes. | PASS | Limits are 30 seconds, 160 MiB RSS, and 15 MiB executable size on this machine. |
| Documentation | Both READMEs already describe the beta. `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`, and `docs/RELEASING.md` now cover provenance, threat boundaries, cost-adapter proof, price-catalog review, and resource checks. | PASS | Price references still require review whenever the bundled catalog changes. |

## Merge decision

The rebased source is ready for normal review and merge as a beta. It preserves
quota behavior, keeps all cost features disabled until explicit opt-in, and
passes the local build, test, formatting, privacy, resource, and diff gates.

Because rebasing rewrites the pull-request branch, hosted CI must run again on
the updated remote head. Merge only after those new checks pass. Live provider
account observations may improve beta confidence, but the feature neither
requires nor claims a production billing reconciliation.
