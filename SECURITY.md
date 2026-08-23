# Security Policy

## Secret handling

TokenLink stores provider API keys exclusively in the macOS Keychain under the
service `io.github.phantom5125.tokenlink.provider`, one account per provider.
Keys are never written to `config.json`, logs, diagnostics, or Git.

- Configuration files contain no secrets; `scripts/privacy_scan.sh` runs in CI
  to keep it that way.
- Diagnostics exported from the app are recursively redacted (usernames, home
  paths, Bluetooth identifiers, account labels, and any key matching
  `token|secret|authorization|api[_-]?key`).
- The Kimi adapter may read the local Kimi Code CLI credential file read-only;
  it never reads or writes the refresh token.
- Network requests are validated against per-provider HTTPS host allowlists
  before any credential-bearing header is attached.

## Reporting a vulnerability

Please do not open a public issue for security reports. Email the maintainer
listed on the GitHub repository profile, or use GitHub's private vulnerability
reporting. Include reproduction steps and affected versions; secrets must never
be included in the report.
