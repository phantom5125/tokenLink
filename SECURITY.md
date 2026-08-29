# Security Policy

## Supported versions

Security fixes are made against the current `main` branch and, when practical,
the most recent published release. Older commits, forks, and independently
distributed builds do not receive guaranteed security updates.

## Secret handling

TokenLink stores explicit provider API keys exclusively in the macOS Keychain
under service `io.github.phantom5125.tokenlink.provider` and stable per-account
identifiers. Keys are never written to `config.json`, logs, diagnostics, or Git.

- Configuration files contain no secrets; `scripts/privacy_scan.sh` runs in CI
  to keep it that way.
- Diagnostics exported from the app are recursively redacted (usernames, home
  paths, Bluetooth identifiers, account labels, and any key matching
  `token|secret|authorization|api[_-]?key`).
- The Kimi adapter may read the documented local Kimi Code CLI credential file
  read-only. The Claude adapter may read the Claude Code Keychain credential
  read-only. Neither adapter reads or writes a refresh token.
- The initial destination of each credential-bearing request is validated
  against its provider's HTTPS host allowlist before the request is sent.
- Codex quota and task state reuse the local Codex CLI sign-in. The optional
  usage observer reads only documented CLI session roots and summarizes token
  counters locally.
- Protocol v2 sends provider/window labels, quota values, display settings, and
  up to three short visible Codex task titles/states to the explicitly bound
  watch. It does not send credentials, account identifiers, raw prompts,
  transcripts, response bodies, or audio.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Email [nico_ying@163.com](mailto:nico_ying@163.com) with a subject beginning
`[TokenLink Security]`. Include:

- the affected version or commit;
- impact and realistic attack conditions;
- minimal reproduction steps or a proof of concept;
- relevant macOS, provider, device, and firmware versions; and
- any suggested mitigation.

Never include real API keys, access or refresh tokens, cookies, complete private
provider responses, personal paths, account identifiers, or Bluetooth UUIDs.
Use synthetic or aggressively redacted evidence.

TokenLink is a personal project, so no response or remediation deadline is
guaranteed. Reports will be handled on a best-effort basis, with priority given
to demonstrated impact and reproducibility. Please allow a reasonable period for
investigation before public disclosure.

## Adapter evidence

Provider and hardware adapter contributions require compatibility evidence, but
that evidence must not weaken user security. Public pull requests should contain
only synthetic fixtures and redacted screenshots, recordings, or log excerpts.
If reproducing a security-sensitive integration requires private material,
coordinate through the reporting channels above before submitting the adapter.
