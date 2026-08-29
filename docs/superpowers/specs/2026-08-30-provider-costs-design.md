# Provider Costs Beta Design

Status: chat design approved; awaiting written review

Date: 2026-08-30

Base branch: `codex/watch-face-v2` at `6342486`

Implementation branch: `feat/provider-costs`

## 1. Purpose and priority

TokenLink's primary job remains quota visibility and StopWatch synchronization.
This project adds a separate beta cost domain for two different kinds of data:

1. authoritative financial data returned by a provider API; and
2. API-equivalent cost estimates derived from local CLI usage records.

Quota refresh, menu-bar quota severity, notifications, BLE payloads, and watch
protocols must continue to work when the cost beta is disabled, unavailable,
refreshing, or failing. Cost work must never block quota refresh or device sync.

## 2. Scope

### 2.1 Initial authoritative sources

- OpenRouter account credits and key-period spend:
  - `GET https://openrouter.ai/api/v1/credits`
  - `GET https://openrouter.ai/api/v1/key`
- DeepSeek account balances:
  - `GET https://api.deepseek.com/user/balance`

OpenRouter reports lifetime credits and usage through `/credits`; TokenLink
derives remaining balance as `max(total_credits - total_usage, 0)`. `/key`
supplies any available daily, weekly, monthly, or key-limit spend. The two
requests are independent: usable data from one remains visible if the other is
unavailable or forbidden.

DeepSeek balances remain in the currencies returned by the service. TokenLink
does not infer spend from changes in balance because top-ups, grants, refunds,
and expiry make that inference unreliable.

### 2.2 Initial local estimates

- Codex rollout JSONL below `.codex/sessions`
- Claude transcript JSONL below `.claude/projects`
- Kimi wire JSONL below `.kimi-code/sessions`

The estimate window is the most recent seven days. Every estimate is labelled
`Estimated/API-equivalent` in the UI. It is not a claim about the value or
billing of a Coding Plan subscription.

### 2.3 Deferred sources

The following are outside this implementation because they require organization
or administrator credentials and different authorization semantics:

- OpenAI organization usage and cost APIs
- Anthropic organization usage and cost APIs
- Cursor Team Admin API
- GitHub Copilot organization or enterprise usage APIs

MiniMax and GLM local estimates are also deferred because the approved local
sources do not provide sufficiently reliable model-level usage records.

## 3. Non-goals

- No currency conversion or exchange-rate download.
- No inferred monetary value for quota percentages.
- No financial data in BLE payloads or watch commands.
- No cost-driven quota alert level, menu-bar color, or notification policy.
- No analytics, telemetry, or remote TokenLink service.
- No browser-cookie access, refresh-token handling, or credential-file writes.
- No persistence of balances or estimated monetary totals in this beta.
- No remote price-catalog update in the background.

## 4. Architecture

### 4.1 Parallel domains

Quota and cost share a stable provider identity but use separate domain models,
provider protocols, state stores, refresh entry points, and UI presentation.

`ProviderID` gains `openrouter` and `deepseek`. `ProviderRegistry` gains explicit
capabilities for each provider:

- `quota`
- `authoritativeCost`
- `localCostEstimate`

The existing quota registry and `QuotaProvider` protocol remain unchanged.
OpenRouter and DeepSeek do not receive a fake `ProviderSpec` or a synthetic
`QuotaSnapshot`; they implement the new `CostProvider` protocol. Codex, Claude,
and Kimi keep their quota adapters, while their local transcript readers feed
the estimate pipeline.

Provider enumeration must use capabilities rather than assuming every
`ProviderID` has quota data. In particular:

- default accounts remain the existing quota providers;
- OpenRouter and DeepSeek accounts are opt-in;
- quota refresh filters to `quota` capability;
- watch settings filter to `quota` capability;
- cost-only providers never appear as disabled quota rows.

### 4.2 Cost model

All monetary arithmetic uses Foundation `Decimal`; `Double` is forbidden for
stored prices, balances, cost multiplication, and totals.

The core cost domain consists of the following concepts:

- `CurrencyAmount`: a decimal amount and uppercase ISO 4217 currency code.
- `AccountBalance`: available amount plus optional purchased and used amounts.
- `AuthoritativeCostSnapshot`: provider/account identity, balances, optional
  provider-reported period spend, and fetch time.
- `NormalizedModelUsage`: provider, model ID, timestamp, uncached input, cache
  read, cache write, output tokens, and a deduplication key.
- `ModelCostLineItem`: normalized usage, resolved catalog entry, calculated
  amount, and estimate warnings.
- `EstimatedCostSnapshot`: provider, seven-day period, per-model line items,
  per-currency totals, unknown models, catalog version, catalog effective date,
  and scan time.

Authoritative and estimated snapshots are different concrete types. A single
optional-heavy snapshot type must not make it possible to present an estimate
as authoritative data.

### 4.3 State and coordination

`CostStore` owns last-known-good cost states independently from `ProviderStore`.
An authoritative state is keyed by provider account UUID; a local estimate is
keyed by provider ID because local logs cannot be reliably attributed to a
TokenLink-configured account.

`CostDashboardModel` is the main-actor presentation coordinator. It exposes
authoritative rows, estimate rows, refresh state, errors, the selected menu-bar
supplement, and a separate `refreshCosts(force:)` operation. `AppModel` composes
it but does not absorb its provider or scanner implementation.

## 5. Configuration and credentials

`AppConfiguration` gains:

- `betaCostsEnabled`, default `false`;
- `menuBarCostMetric`, defaulting to the Codex seven-day estimate when cost beta
  is first enabled;
- opt-in OpenRouter and DeepSeek provider accounts in the existing account list.

Decoding an older configuration supplies these defaults without rewriting the
configuration until the user changes a setting.

OpenRouter and DeepSeek keys use the existing Keychain service
`io.github.phantom5125.tokenlink.provider` and provider-plus-account UUID naming.
OpenRouter accepts an explicit user-supplied Management Key or API key. The UI
explains that `/credits` requires Management Key permission; a key that can
access only `/key` yields partial data rather than making the provider wholly
unavailable. DeepSeek accepts an explicit API key. Neither provider reads
browser state or an unrelated application's credential store.

When cost beta is disabled:

- no cost HTTP request is started;
- no local cost scan is started;
- no cost task or timer remains active;
- the menu bar is quota-only.

## 6. Authoritative provider behavior

Both adapters reuse `HTTPClient`, `EndpointPolicy`, redirect rejection, the
20-second request bound, Keychain credential resolution, and official-host
allowlisting.

### 6.1 OpenRouter

Allowed host: `openrouter.ai`.

`/credits` and `/key` run independently. Each successful response is parsed
through typed `Decodable` structures with numeric fields accepting JSON numbers
or numeric strings, rejecting booleans and non-finite values.

- `total_credits` is the purchased/lifetime ceiling.
- `total_usage` is authoritative lifetime usage.
- remaining is `max(total_credits - total_usage, 0)`.
- `/key` period usage and limit fields are presented only when supplied.

A partial response produces usable data plus a warning. Authentication failure
is reported only when no usable endpoint data remains and all attempted
endpoints rejected the credential. Raw response bodies and headers are never
logged.

### 6.2 DeepSeek

Allowed host: `api.deepseek.com`.

Each returned balance becomes a separate `AccountBalance` using the service's
currency. `is_available` is retained as provider status. A zero balance is valid
authoritative data, not missing data.

## 7. Local streaming and estimation

### 7.1 Reader limits

Production local scans must not call `Data(contentsOf:)` for transcript files.
`JSONLStreamingReader` reads 64 KiB chunks, keeps records intact across chunk
boundaries, and checks cancellation between chunks and records.

- maximum source file size: 50 MiB;
- maximum JSONL record size: 1 MiB;
- files are processed sequentially in path order;
- records exceeding the limit are skipped and counted in a sanitized warning;
- files older than the seven-day window are skipped by modification time;
- unreadable files are skipped without exposing their paths in UI or logs.

The scanner aggregates as records arrive. It does not retain raw lines or a
whole-file event array. A deduplication set may retain non-empty event IDs for
the scan window; no prompt or response text enters that set.

### 7.2 Normalized token categories

Provider parsers translate their source semantics into four independent
billable buckets:

- uncached input;
- cache read;
- cache write;
- output.

For Codex, cached input is a subset of input, so uncached input is
`max(input - cached, 0)`. Parser state tracks the current model and cumulative
totals per file, ignores repeated cumulative snapshots, and does not charge
replayed parent history in child rollouts.

For Claude, ordinary input, cache-read input, cache-creation input, and output
are separate source fields. Message ID is the deduplication key. If cache-write
duration is unavailable, the catalog's five-minute cache-write rate is used and
the line item carries a warning.

For Kimi, `inputOther`, `inputCacheRead`, `inputCacheCreation`, and `output` map
directly, and the top-level model field supplies the model ID.

### 7.3 Price calculation

The bundled catalog records, per model and currency, prices per million tokens
for uncached input, cache read, five-minute cache write, optional one-hour cache
write, and output.

For every category:

`category cost = Decimal(token count) * price per million / 1_000_000`

Calculations retain Decimal precision. Rounding happens only during localized
currency formatting. Totals group by currency; currencies are never implicitly
combined.

If a model is unknown, or a used category lacks a price, that model contributes
no money to totals and appears under `Unknown/unpriced models`. This prevents a
partial price from silently undercounting cost.

## 8. Price catalog

The catalog is a read-only application resource with:

- a schema version;
- a catalog version;
- an effective date;
- exact model IDs and explicit aliases;
- category prices and currency;
- a first-party pricing source URL for every entry.

Initial sources are the official OpenAI, Anthropic, and Moonshot pricing pages.
The implementation includes only model IDs verified against supported local
record schemas and official pricing. Adding or changing a price requires a
fixture/test update and review of its source/effective date.

The app does not fetch a live price list. This makes estimates reproducible and
prevents a background pricing service from expanding TokenLink's network or
privacy surface.

## 9. Refresh and failure behavior

The Costs page is always discoverable and displays an enablement explanation
when the beta is off. Enabling the beta does not immediately scan; the first
Costs-page visit triggers an initial load.

- authoritative snapshot TTL: 15 minutes;
- local estimate TTL: 30 minutes;
- manual `Refresh costs` bypasses both TTLs;
- one in-flight operation is allowed per source;
- duplicate refresh requests coalesce;
- one failed source does not delay or erase another source;
- failure retains last-known-good data and marks it stale;
- no prior success produces a typed missing-credential, authentication,
  network, decoding, timeout, or local-read state.

Cost refresh is separate from the existing quota toolbar refresh. Quota refresh
must not start a scan. Cost refresh must not start quota or watch synchronization.

Snapshots and monetary values remain in memory for this beta. A later persistent
cache design must separately address financial-data privacy, account identity,
schema migration, and stale-on-launch behavior.

## 10. User interface

### 10.1 Costs route

Control Center gains a `Costs β` route between Providers and StopWatch. It has:

- `Authoritative balances` cards for configured OpenRouter and DeepSeek accounts;
- `Estimated API-equivalent cost` cards for Codex, Claude, and Kimi;
- source/provenance text, period, price-catalog effective date, last update, and
  stale/error status on every card;
- a dedicated `Refresh costs` action.

OpenRouter and DeepSeek credential/account controls live in Providers with a
cost-beta badge. They do not appear in quota overview rows or watch-provider
selection. A generic text/monogram mark is acceptable for the beta; third-party
logo assets are not required.

All new user-facing strings cover English, Simplified Chinese, and Japanese.

### 10.2 Menu-bar text

Quota remains first. Cost changes text only; quota alone controls menu-bar icon,
color, severity, and ordering.

When beta is enabled, Settings offers a fixed cost metric selection:

- one provider's seven-day estimate;
- an OpenRouter account balance;
- one DeepSeek account/currency balance;
- none.

The selection never rotates automatically. Examples:

- `Codex 42% · ≈$8.31/7d`
- `Codex 42% · OR $18.40 left`
- `Codex 42% · DS ¥72 left`

`≈` is mandatory for estimates. Authoritative balances use `left` and no
estimate marker. A missing or failed selection falls back to the existing
quota-only label. Stale cost text remains visible with a stale accessibility
description. Accessibility labels spell out provider, source, amount, period,
and freshness rather than relying on abbreviations.

## 11. Privacy and diagnostics

Local readers extract only timestamps, model IDs, token counters, and
deduplication IDs. They do not retain prompts, responses, tool content, paths,
account identifiers, or raw JSONL.

Diagnostic export includes only beta enabled state, cost phase, source kind,
refresh time, catalog version, and error category. It excludes balances,
spend amounts, model totals, filenames, account labels, and Keychain hints.

Application logs exclude keys, authorization headers, raw bodies, paths, and
monetary amounts. There is no analytics or telemetry.

## 12. Resource budgets and CI

The pre-feature baseline on the development Mac is approximately 58.3 MiB peak
RSS for the full test process and 3.9 MiB for the release executable.

CI adds a macOS resource job that builds first, then measures the already-built
test/resource workload so compiler memory is not confused with application
memory. A deterministic 64 MiB synthetic JSONL source exercises the streaming
scanner.

Initial gates:

- streaming workload peak RSS: at most 160 MiB;
- 64 MiB scan wall time: at most 30 seconds;
- release executable size: at most 15 MiB.

The resource workload verifies aggregate counts instead of merely measuring a
process that did no useful work. Thresholds may be tightened only after several
stable CI runs; a threshold increase requires a documented reason in the same
change.

Structural tests also assert reader chunk size, maximum record size, file-size
boundary, cancellation, and no whole-file production read.

## 13. Test and acceptance matrix

Implementation follows test-driven development. Required coverage includes:

- Decimal arithmetic for every token category, currency grouping, aliases,
  and display rounding;
- unknown model and missing category prices excluded from totals;
- OpenRouter credits/key success, partial success, zero balance, auth failure,
  malformed numeric values, host validation, and redirect rejection;
- DeepSeek multiple currencies, zero balance, unavailable status, auth failure,
  malformed response, host validation, and redirect rejection;
- JSONL records split across chunks, a record exactly at and over 1 MiB, a file
  exactly at and over 50 MiB, cancellation, unreadable files, and Claude dedupe;
- Codex model state, repeated cumulative totals, cached-input subtraction, and
  child replay suppression;
- Claude and Kimi category mapping;
- beta-disabled guarantees of zero network and zero local scans;
- TTL, force refresh, coalescing, partial failure, and last-known-good state;
- configuration migration, Keychain account naming, and cost-only capability
  filtering from quota/watch flows;
- Costs route states and localized strings;
- menu-bar estimate marker, authoritative label, fixed selection, stale
  accessibility text, and quota-only fallback;
- privacy scan and diagnostic omission of monetary/account details;
- the CI resource workload and binary-size gates.

Before completion, the branch must pass:

```bash
swift build
bash scripts/test.sh
swift format lint --strict Package.swift
swift format lint --recursive --strict Sources Tests
bash scripts/privacy_scan.sh
bash scripts/resource_check.sh
git diff --check
```

## 14. Authoritative references

- OpenRouter credits API:
  <https://openrouter.ai/docs/client-sdks/python/api-reference/credits>
- OpenRouter usage accounting:
  <https://openrouter.ai/docs/cookbook/administration/usage-accounting>
- DeepSeek balance API:
  <https://api-docs.deepseek.com/api/get-user-balance/>
- OpenAI API pricing:
  <https://openai.com/api/pricing/>
- Anthropic pricing and prompt caching:
  <https://platform.claude.com/docs/en/about-claude/pricing>
- Moonshot platform documentation:
  <https://platform.moonshot.ai/docs/>
