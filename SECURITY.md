# Security policy

## Supported versions

TokenLink is pre-1.0 software. Security fixes are applied to the latest `main`
branch and the newest published release.

## Reporting a vulnerability

Please do not open a public issue for suspected credential exposure, host-policy
bypass, unsafe diagnostics, or Bluetooth binding flaws. Use GitHub's private
security-advisory reporting for this repository. Include the affected revision,
reproduction steps, impact, and whether a real credential or device identifier
was involved. Do not include live secrets; revoke any credential that may have
been exposed.

## Credential boundary

- Explicit provider API keys are generic-password items in macOS Keychain.
- The service is `io.github.phantom5125.tokenlink.provider`; the account is the
  stable provider ID (`kimi`, `minimax`, or `glm`).
- Codex authentication remains owned by the local Codex CLI/app-server.
- Kimi CLI reuse is read-only and limited to the documented credential file and
  its current access token. Refresh tokens are neither decoded nor returned.
- Browser cookies, unrelated credential databases, and Full Disk Access are out
  of scope and must not be added without a new public security design.

## Network boundary

Credential-bearing HTTP requests require HTTPS and an adapter-specific official
host allowlist. Redirects or configurable endpoints must not widen that boundary
silently. Provider response data is treated as untrusted and decoded into explicit
structures.

## Device boundary

TokenLink initializes CoreBluetooth only for an explicit discovery action or a
previously bound-device sync. Discovery checks connected private-service/HID
peripherals and uses a short broad scan filtered by the `Codex Micro` name or the
private quota-service UUID. It persists one user-selected CoreBluetooth identifier
and never connects a discovery candidate before binding. Version 1 sends only the
normalized Codex primary-window payload. Connect/write operations have deadlines,
bounded retry, and disconnect-state reporting.

## Diagnostics

Diagnostic export is user initiated. Redaction removes sensitive keys, bearer
values, home paths, usernames, account labels, and UUID-shaped device identifiers
before data is written. Changes to diagnostics require adversarial redaction tests.
