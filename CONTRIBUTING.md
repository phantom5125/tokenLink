# Contributing

Thanks for helping improve TokenLink.

## Development setup

- macOS 14+, Swift 6.2 toolchain or newer.
- `swift build` / `swift test` with Xcode, or on Command-Line-Tools-only
  machines use the same commands for compilation and any Swift Testing runner
  for execution.

## Adding a provider

1. Add the `ProviderID` case and its display descriptor in `TokenLinkCore`.
2. Create `Sources/TokenLinkProviders/<Name>/` with:
   - a `<Name>Parser` that decodes the provider response into `QuotaSnapshot`
     using explicit `Decodable` structs — never infer limits from plan names;
   - a `<Name>Provider` that fetches via `HTTPClient` with an
     `EndpointPolicy` allowlisting only the provider's hosts, and maps
     401/403 to `.authentication`.
3. Add a synthetic (never real) response fixture under
   `Tests/TokenLinkProviderTests/Fixtures/` plus parser and provider tests.
4. Wire the provider into `AppModel.live()`.
5. Run `swift build`, the full test suite, `swift format lint --recursive
   --strict Sources Tests`, and `bash scripts/privacy_scan.sh`.

## Rules that keep the project safe

- No secrets, personal paths, or real device UUIDs in tracked files
  (`scripts/privacy_scan.sh` enforces this).
- Watch protocol v1 carries only the Codex primary window — do not project
  other providers onto the legacy StopWatch payload.
- Keep commits scoped to one task; write tests before implementation.
