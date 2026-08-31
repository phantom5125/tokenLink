# Contributing to TokenLink

Thank you for helping improve TokenLink. Code, tests, documentation, design
feedback, reproducible bug reports, and real-world adapter validation are all
valuable contributions.

TokenLink is maintained as a personal open-source project. Maintainer time,
coding-plan capacity, provider accounts, and hardware access are limited. There
is no guaranteed response time, roadmap commitment, or obligation to merge a
contribution. Clear scope and verifiable evidence make a contribution much
easier to review and maintain.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Choose the right starting point

| Change | Start with |
| --- | --- |
| Typo, docs, focused test, or small verified bug fix | Pull request |
| Bug whose cause or safe fix is uncertain | A bug report |
| New behavior, UI, protocol, or architecture | Feature proposal first |
| New provider or hardware adapter | An adapter proposal with a validation plan |
| Security or privacy concern | A private security report, never a public issue |

Search existing issues and pull requests before starting. Keep one problem or
proposal per issue. A large implementation submitted without prior agreement may
be closed even when it works, because every feature creates a long-term
maintenance obligation.

Well-scoped issues are especially welcome. The maintainer may use coding agents
to implement an accepted proposal in a way that stays consistent with the
architecture. An issue that explains the problem, constraints, and proof of
success can therefore be more useful than a large speculative pull request.

## What makes a change reviewable

A pull request should:

- solve one clearly stated problem;
- link the related issue when prior discussion was required;
- explain expected and actual behavior;
- include the smallest relevant automated test when behavior changes;
- list the exact verification commands that ran and their results;
- include redacted screenshots, logs, or hardware evidence when automated tests
  cannot prove the result;
- avoid unrelated formatting or refactoring; and
- update user or contributor documentation when an interface or workflow changes.

If a check could not run, say why. A disclosure is better than an unsupported
claim.

## AI- and agent-assisted contributions

AI-assisted work is welcome. The person opening the pull request remains
responsible for the contribution.

- Read and understand every submitted change.
- Verify behavior with the same care as human-written code.
- Disclose material AI or agent assistance in the pull request.
- Do not submit generated code, text, or assets whose provenance or license you
  cannot explain.
- Never provide an agent with real API keys, private account payloads, personal
  paths, device UUIDs, or other secrets for inclusion in the repository.

The maintainer may ask for a smaller patch, additional tests, or a human
explanation of the design before reviewing generated changes.

## Development setup

Requirements:

- macOS 14 or newer;
- Swift 6.2 toolchain or newer; and
- full Xcode for the standard Swift Testing runner and UI-level validation.

Build and run the project:

```bash
swift build
bash scripts/test.sh
swift run tokenlink
```

Before opening a pull request, run:

```bash
swift build
bash scripts/test.sh
swift format lint --strict Package.swift
swift format lint --recursive --strict Sources Tests
bash scripts/privacy_scan.sh
bash scripts/resource_check.sh
```

On a Command-Line-Tools-only machine, compilation may work while the Swift
Testing runner is unavailable. State that limitation in the pull request and
use the macOS CI result as the test evidence.

## Provider adapter contributions

TokenLink uses a narrow, adapter-oriented architecture:

- `TokenLinkCore` owns provider-neutral identifiers, quota and cost snapshots,
  and state;
- `TokenLinkProviders` contains isolated provider parsers and fetchers;
- quota providers implement `QuotaProvider` and emit a normalized
  `QuotaSnapshot`;
- authoritative cost providers use their own capability, adapter, snapshot,
  store, and refresh path; and
- the app supplies credentials and HTTP access through narrow interfaces.

Adapters are currently compiled into TokenLink. They are plugin-like extension
points, not dynamically loaded third-party plugins or a stable plugin ABI. A
proposal for runtime plugin loading is an architectural feature and must be
discussed separately.

To add a provider:

1. Add the `ProviderID` case and its display descriptor in `TokenLinkCore`.
2. Create `Sources/TokenLinkProviders/<Name>/` with:
   - a `<Name>Parser` that decodes the response into `QuotaSnapshot` using
     explicit `Decodable` structs;
   - a `<Name>Provider` that fetches through `HTTPClient`;
   - an `EndpointPolicy` that allowlists only the provider's documented HTTPS
     hosts; and
   - explicit authentication and error mapping. Never infer limits from a plan
     name.
3. Add synthetic response fixtures under
   `Tests/TokenLinkProviderTests/Fixtures/`. Never commit a real account
   response.
4. Add parser tests and provider tests for success, authentication failure,
   malformed data, and disallowed endpoints.
5. Wire the provider into `AppModel.live()` and document credential setup.
6. Attach the validation evidence described below.

### Required provider proof

An adapter pull request must include:

- a link to official endpoint or protocol documentation, or a clear explanation
  of how the interface was established;
- provider region and plan type tested, without account identifiers;
- a redacted screenshot or screen recording showing a successful refresh in
  TokenLink;
- the date and TokenLink commit used for the real-account check; and
- passing synthetic fixture and provider tests.

Do not publish tokens, cookies, request headers, raw private payloads, usernames,
home paths, subscription identifiers, or exact quota values when they could
identify an account. It is acceptable to obscure account-specific values while
showing that the expected windows, reset behavior, and status are present.

## Cost provider and pricing contributions

Quota, authoritative balances, and local cost estimates are separate domains.
A cost-only provider must not receive a synthetic quota snapshot, affect quota
severity or notifications, or enter a StopWatch payload.

An authoritative cost adapter must:

- use an official account or billing endpoint with a narrow HTTPS host policy;
- require an explicit Keychain credential rather than browser state or an
  unrelated CLI credential;
- preserve returned currencies and valid zero values without conversion or
  inference from balance changes;
- distinguish authentication, timeout, decoding, and partial-source failures;
  and
- include synthetic fixture tests without real account payloads or amounts.

A price-catalog change must include the catalog version and effective date,
first-party pricing references, explicit model aliases, and independent rates
for every supported token bucket. Never guess an unknown model price, silently
price a partially covered record, convert currencies, or remove the visible
`Estimated/API-equivalent` label. Update estimator tests and the resource
workload when a new local transcript format is introduced.

## Hardware adapter contributions

Hardware and firmware access is not assumed. A hardware contribution must state:

- exact hardware model and firmware version;
- discovery and binding steps;
- protocol identifiers or an authoritative protocol reference;
- evidence for discovery, connection, acknowledged write, and visible device
  update as separate checkpoints; and
- whether the maintainer can reproduce the result without owning the device.

Attach a redacted photo, video, or log excerpt demonstrating the integration.
Never include a real Bluetooth UUID or other persistent device identifier.

The legacy StopWatch protocol v1 carries only the Codex primary window. Do not
project other providers onto that payload or label non-Codex data as Codex.
Protocol v2 additions must keep that byte-compatible fallback, enforce the
payload size limit, add fake-transport coverage, and link a matching companion
firmware revision. Physical claims still require separate C152 observations.

When the maintainer lacks the required account, plan, or hardware, an adapter may
remain experimental, live in a separately maintained fork, or wait for another
community member to reproduce it. This is a maintenance decision, not a judgment
on the effort involved.

## Pull request workflow

1. Fork the repository and create a focused branch.
2. Add or update tests before changing behavior.
3. Make the smallest change that satisfies the agreed scope.
4. Run the verification commands.
5. Complete every applicable section of the pull request template.
6. Respond to review with focused commits; avoid rewriting unrelated history.

Keep commits scoped and use descriptive subjects such as
`fix: handle missing provider window` or `docs: clarify adapter evidence`.
Maintainer release checks are documented separately in
[`docs/RELEASING.md`](docs/RELEASING.md).

## Contribution licensing

TokenLink is licensed under the [Apache License 2.0](LICENSE). Unless you
explicitly state otherwise, any contribution intentionally submitted for
inclusion in TokenLink is submitted under the same license, without additional
terms or conditions, as described in section 5 of the Apache License 2.0.

Only submit work that you have the right to license. Preserve applicable
third-party notices and identify any borrowed or adapted material in the pull
request.
