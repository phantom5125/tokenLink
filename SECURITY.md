# Security Policy

## Supported versions

Security fixes are made against the current `main` branch and, when practical,
the most recent published release. Older commits, forks, and independently
distributed builds do not receive guaranteed security updates.

## Secret handling

TokenLink stores explicit provider API keys exclusively in the macOS Keychain
under service `app.tokenlink.provider` and stable per-account
identifiers. Keys are never written to `config.json`, logs, diagnostics, or Git.

The pre-0.2.1 service `io.github.phantom5125.tokenlink.provider` is never read
during launch, scheduled refresh, or credential-status checks. Existing users
may start a one-time migration from the Providers screen after reviewing its
scope; TokenLink copies only configured Kimi, MiniMax, and GLM items and keeps
the old items as a recovery fallback.

- Configuration files contain no secrets; `scripts/privacy_scan.sh` runs in CI
  to keep it that way.
- Diagnostics exported from the app are recursively redacted (usernames, home
  paths, Bluetooth identifiers, account labels, and any key matching
  `token|secret|authorization|api[_-]?key`).
- The Kimi adapter may read the documented local Kimi Code CLI credential file
  read-only. TokenLink never requests the Claude Code Keychain credential until
  the user enables Claude, reviews the access explanation, and clicks the
  authorization button. macOS grants access to the whole item; the adapter
  decodes only its access token and expiry and deliberately omits the refresh
  token field. Neither adapter writes a CLI credential or refresh token.
- The initial destination of each credential-bearing request is validated
  against its provider's HTTPS host allowlist before the request is sent.
- Authoritative cost adapters use only explicitly configured Keychain
  credentials. Provider balances, spend values, local estimates, and priceable
  model identifiers remain in memory and are excluded from diagnostics.
- Codex quota and task state reuse the local Codex CLI sign-in. The optional
  usage observer reads only documented CLI session roots plus the non-secret
  top-level `service_tier` in Codex configuration, and summarizes token
  counters locally.
- Local usage and cost scans accept regular files only, refuse symbolic links
  and special files, enforce 256 MiB per-file and 1 MiB per-record limits while
  reading, and never retain prompt or response content.
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
Cost-provider evidence must also obscure account-specific monetary values and
must not include raw billing responses or organization identifiers.
If reproducing a security-sensitive integration requires private material,
coordinate through the reporting channels above before submitting the adapter.
