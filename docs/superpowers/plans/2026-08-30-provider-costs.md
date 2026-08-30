# Provider Costs Beta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in authoritative OpenRouter/DeepSeek balances and seven-day local Codex/Claude/Kimi API-equivalent cost estimates without changing quota or StopWatch behavior.

**Architecture:** Quota and cost share `ProviderID` but have explicit capabilities, separate snapshot types, stores, refresh paths, and UI. Authoritative providers live in `TokenLinkProviders`; Decimal money models and state live in `TokenLinkCore`; bounded JSONL scanning and presentation coordination live in `TokenLinkApp`.

**Tech Stack:** Swift 6.2, Foundation `Decimal`, Swift Concurrency actors, SwiftUI/Observation, Swift Testing, macOS Keychain, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-30-provider-costs-design.md`

## Global Constraints

- Quota refresh, BLE payloads, notifications, and StopWatch synchronization must remain independent from all cost work.
- Cost beta defaults to disabled and starts no HTTP request, scan, timer, or task while disabled.
- Every local monetary result is labelled exactly `Estimated/API-equivalent`; menu-bar estimates always include `≈`.
- Monetary arithmetic uses `Decimal`; no stored balance, price, multiplication, or total uses `Double`.
- Authoritative TTL is 15 minutes; local estimate TTL is 30 minutes; manual cost refresh bypasses both.
- JSONL reads use 64 KiB chunks, reject records over 1 MiB, and skip files over 256 MiB.
- Local data remains in memory. Logs and diagnostics omit balances, spend, monetary totals, account labels, UUIDs, paths, raw JSON, and secrets.
- English, Simplified Chinese, and Japanese strings are required for every new UI string.
- CI gates a deterministic 64 MiB scan at 160 MiB peak RSS and 30 seconds, and a release executable at 15 MiB.

---

## File Structure

### TokenLinkCore

- `Sources/TokenLinkCore/ProviderModels.swift`: add cost-only provider IDs and provider capability values.
- `Sources/TokenLinkCore/CostModels.swift`: Decimal amounts, authoritative snapshots, normalized usage, price entries, estimates, warnings, and menu-bar selection values.
- `Sources/TokenLinkCore/CostStore.swift`: independent authoritative/estimate state and last-known-good failure handling.
- `Tests/TokenLinkCoreTests/CostModelsTests.swift`: hand-calculated Decimal totals, aliases, unknown models, and currency grouping.
- `Tests/TokenLinkCoreTests/CostStoreTests.swift`: success, stale retention, and aging behavior.

### TokenLinkProviders

- `Sources/TokenLinkProviders/Shared/ProviderSpec.swift`: capability registry and names for cost-only providers.
- `Sources/TokenLinkProviders/Costs/AuthoritativeCostProvider.swift`: provider/account bindings and credential/HTTP helpers shared by financial adapters.
- `Sources/TokenLinkProviders/Costs/OpenRouterCostProvider.swift`: independent `/credits` and `/key` requests and partial-success merge.
- `Sources/TokenLinkProviders/Costs/DeepSeekCostProvider.swift`: `/user/balance` parsing with multi-currency preservation.
- `Sources/TokenLinkProviders/Costs/PriceCatalog.swift`: bundled catalog decoding and alias resolution.
- `Sources/TokenLinkProviders/Resources/api-equivalent-prices.json`: reviewed first-party API prices and source/effective-date metadata.
- `Tests/TokenLinkProviderTests/AuthoritativeCostProviderTests.swift`: endpoint, credential, numeric decoding, partial failure, and host-policy behavior.
- `Tests/TokenLinkProviderTests/PriceCatalogTests.swift`: resource schema and exact alias resolution.
- `Tests/TokenLinkProviderTests/Fixtures/openrouter-credits.json`: complete credits response fixture.
- `Tests/TokenLinkProviderTests/Fixtures/openrouter-key.json`: complete current-key response fixture.
- `Tests/TokenLinkProviderTests/Fixtures/deepseek-balance.json`: complete multi-currency balance fixture.

### TokenLinkApp

- `Sources/TokenLinkApp/ConfigurationStore.swift`: beta setting, fixed menu-bar metric, and opt-in cost accounts.
- `Sources/TokenLinkApp/LocalUsage/JSONLStreamingReader.swift`: bounded cancellable record reader.
- `Sources/TokenLinkApp/LocalUsage/LocalUsageModels.swift`: model-aware four-bucket normalized usage and streaming parser contract.
- `Sources/TokenLinkApp/LocalUsage/LocalUsageReaders.swift`: stateful Codex, Claude, and Kimi record parsers.
- `Sources/TokenLinkApp/LocalUsage/LocalUsageObserver.swift`: sequential bounded file enumeration and streaming aggregation.
- `Sources/TokenLinkApp/Costs/LocalCostEstimator.swift`: seven-day catalog pricing and unknown-model reporting.
- `Sources/TokenLinkApp/Costs/CostDashboardModel.swift`: TTL, coalescing, force refresh, independent source errors, and menu supplement.
- `Sources/TokenLinkApp/AppModel.swift`: compose cost dashboard, expose settings actions, and keep quota/watch filters capability-based.
- `Sources/TokenLinkApp/Views/CostsView.swift`: opt-in explanation, authoritative cards, estimate cards, provenance, freshness, and manual refresh.
- `Sources/TokenLinkApp/Views/ControlCenterView.swift`: add `Costs β` route and route-specific toolbar refresh.
- `Sources/TokenLinkApp/Views/MenuBarView.swift`: show selected cost supplement without changing quota severity.
- `Sources/TokenLinkApp/Views/ProvidersView.swift`: cost-only OpenRouter/DeepSeek account and credential controls.
- `Sources/TokenLinkApp/Views/SettingsView.swift`: beta toggle and fixed metric picker.
- `Sources/TokenLinkApp/Views/ViewSupport.swift`: monogram/symbol/color fallback for the two cost-only providers.
- `Sources/TokenLinkApp/Strings.swift`: complete three-language cost catalog.
- `Sources/TokenLinkApp/DiagnosticExporter.swift`: preserve redaction boundary for cost diagnostic metadata.
- `Tests/TokenLinkAppTests/ConfigurationStoreTests.swift`: migration/default/round-trip behavior.
- `Tests/TokenLinkAppTests/JSONLStreamingReaderTests.swift`: chunk, record, file, cancellation, and unreadable-source boundaries.
- `Tests/TokenLinkAppTests/LocalCostEstimatorTests.swift`: model-aware parser and estimate behavior.
- `Tests/TokenLinkAppTests/CostDashboardModelTests.swift`: disablement, TTL, coalescing, force refresh, and partial failure.
- `Tests/TokenLinkAppTests/AppModelTests.swift`: quota/watch filtering, menu label, and diagnostic omission.
- `Tests/TokenLinkAppTests/LocalizationTests.swift`: existing exhaustive catalog check covers new keys.

### Build and CI

- `Package.swift`: add the provider resource bundle.
- `scripts/resource_check.sh`: build-before-measure resource and executable-size gates.
- `.github/workflows/ci.yml`: add resource-budget job on macOS.

---

### Task 1: Provider Capabilities and Backward-Compatible Configuration

**Files:**
- Modify: `Sources/TokenLinkCore/ProviderModels.swift`
- Create: `Sources/TokenLinkCore/CostModels.swift`
- Modify: `Sources/TokenLinkProviders/Shared/ProviderSpec.swift`
- Modify: `Sources/TokenLinkApp/ConfigurationStore.swift`
- Modify: `Sources/TokenLinkApp/Views/ViewSupport.swift`
- Test: `Tests/TokenLinkProviderTests/ProviderSpecTests.swift`
- Test: `Tests/TokenLinkAppTests/ConfigurationStoreTests.swift`

**Interfaces:**
- Produces: `ProviderCapability: OptionSet`, `ProviderRegistry.capabilities(for:)`, `ProviderRegistry.quotaProviderIDs`, `ProviderRegistry.authoritativeCostProviderIDs`, `ProviderRegistry.localCostEstimateProviderIDs`.
- Produces: `AppConfiguration.betaCostsEnabled: Bool` and `AppConfiguration.menuBarCostMetric: MenuBarCostMetric`.
- Consumes later: every quota/watch/account enumeration must filter using these capabilities.

- [ ] **Step 1: Write failing registry tests**

Add literal behavior checks:

```swift
@Test func registrySeparatesQuotaAndCostCapabilities() {
  #expect(ProviderRegistry.capabilities(for: .codex) == [.quota, .localCostEstimate])
  #expect(ProviderRegistry.capabilities(for: .openrouter) == [.authoritativeCost])
  #expect(ProviderRegistry.capabilities(for: .deepseek) == [.authoritativeCost])
  #expect(!ProviderRegistry.quotaProviderIDs.contains(.openrouter))
  #expect(ProviderRegistry.authoritativeCostProviderIDs == [.openrouter, .deepseek])
}
```

This catches accidentally treating cost-only IDs as quota providers.

- [ ] **Step 2: Run the focused registry test and confirm RED**

Run: `swift test --filter registrySeparatesQuotaAndCostCapabilities`

Expected: compilation fails because the new provider IDs/capabilities do not exist.

- [ ] **Step 3: Add provider IDs, capabilities, names, and UI fallbacks**

Implement:

```swift
public struct ProviderCapability: OptionSet, Sendable, Equatable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }
  public static let quota = Self(rawValue: 1 << 0)
  public static let authoritativeCost = Self(rawValue: 1 << 1)
  public static let localCostEstimate = Self(rawValue: 1 << 2)
}
```

Add `.openrouter` and `.deepseek`, registry mappings, and switch cases. Keep `ProviderRegistry.spec(for:)` quota-only.

- [ ] **Step 4: Run registry tests and confirm GREEN**

Run: `swift test --filter 'registrySeparatesQuotaAndCostCapabilities|registryDisplayNamesCoverCustomProviders'`

Expected: PASS.

- [ ] **Step 5: Write failing configuration migration tests**

Add checks that an old config decodes with `betaCostsEnabled == false`, `.none` menu selection, and no OpenRouter/DeepSeek accounts; also check `.default` contains only quota accounts.

```swift
#expect(loaded.betaCostsEnabled == false)
#expect(loaded.menuBarCostMetric == .none)
#expect(!loaded.accounts.contains { [.openrouter, .deepseek].contains($0.provider) })
#expect(AppConfiguration.default.accounts.allSatisfy {
  ProviderRegistry.capabilities(for: $0.provider).contains(.quota)
})
```

- [ ] **Step 6: Run migration test and confirm RED**

Run: `swift test --filter legacyEnabledProvidersConfigurationMigratesToAccounts`

Expected: compilation fails for missing cost settings.

- [ ] **Step 7: Implement defaults, Codable migration, and enablement semantics**

Create `CostModels.swift` now with `MenuBarCostMetric` cases `.none`, `.localEstimate(ProviderID)`, and `.authoritativeBalance(accountID: UUID, currency: String)`. Decode missing keys as disabled/none. Make default account creation use `quotaProviderIDs`; cost accounts are created only by an explicit add action. Enabling cost beta changes `.none` to `.localEstimate(.codex)` in the AppModel setter, not while merely decoding.

- [ ] **Step 8: Run configuration and provider suites**

Run: `swift test --filter 'ConfigurationStoreTests|ProviderSpecTests'`

Expected: PASS.

- [ ] **Step 9: Commit Task 1**

```bash
git add Sources/TokenLinkCore/ProviderModels.swift Sources/TokenLinkCore/CostModels.swift Sources/TokenLinkProviders/Shared/ProviderSpec.swift Sources/TokenLinkApp/ConfigurationStore.swift Sources/TokenLinkApp/Views/ViewSupport.swift Tests/TokenLinkProviderTests/ProviderSpecTests.swift Tests/TokenLinkAppTests/ConfigurationStoreTests.swift
git commit -m "feat: separate provider quota and cost capabilities"
```

### Task 2: Decimal Cost Domain and Bundled Price Catalog

**Files:**
- Modify: `Sources/TokenLinkCore/CostModels.swift`
- Create: `Sources/TokenLinkProviders/Costs/PriceCatalog.swift`
- Create: `Sources/TokenLinkProviders/Resources/api-equivalent-prices.json`
- Modify: `Package.swift`
- Create: `Tests/TokenLinkCoreTests/CostModelsTests.swift`
- Create: `Tests/TokenLinkProviderTests/PriceCatalogTests.swift`

**Interfaces:**
- Produces: `CurrencyAmount`, `AccountBalance`, `ProviderPeriodSpend`, `AuthoritativeCostSnapshot`, `NormalizedModelUsage`, `ModelPrice`, `ModelCostLineItem`, `EstimatedCostSnapshot`, and `CostWarning`.
- Produces: `PriceCatalog.bundled()`, `entry(provider:modelID:)`, and `estimate(_:)`.
- Consumes: `ProviderID` and `Decimal` only; does not depend on app state.

- [ ] **Step 1: Write failing Decimal arithmetic tests**

Use hand-derived totals, not production helpers:

```swift
@Test func priceCalculationUsesFourIndependentBuckets() throws {
  let usage = NormalizedModelUsage(
    provider: .claude, modelID: "claude-sonnet-4-6",
    timestamp: Date(timeIntervalSince1970: 1), uncachedInputTokens: 1_000_000,
    cacheReadTokens: 1_000_000, cacheWriteTokens: 1_000_000,
    outputTokens: 1_000_000, deduplicationKey: "m1")
  let price = ModelPrice(
    provider: .claude, modelID: "claude-sonnet-4-6", aliases: [], currency: "USD",
    uncachedInputPerMillion: 3, cacheReadPerMillion: 0.3,
    cacheWriteFiveMinutePerMillion: 3.75, cacheWriteOneHourPerMillion: 6,
    outputPerMillion: 15, sourceURL: URL(string: "https://platform.claude.com")!)

  #expect(try CostCalculator.lineItem(usage: usage, price: price).amount.value == Decimal(string: "22.05"))
}
```

Add independent tests for alias lookup, grouped currencies, and an unknown/missing-category model contributing zero money while appearing in `unknownModelIDs`. Add a literal test that a single 272,001-token GPT-5.5 request receives the official 2x input and 1.5x output multipliers while a 272,000-token request does not.

- [ ] **Step 2: Run cost model tests and confirm RED**

Run: `swift test --filter CostModelsTests`

Expected: compilation fails because cost models and calculator are absent.

- [ ] **Step 3: Implement minimal immutable models and calculator**

Normalize currency codes to uppercase, clamp token counts to nonnegative values, multiply with `Decimal(tokenCount) * rate / 1_000_000`, apply optional request-level threshold multipliers before aggregation, and leave rounding to formatting. Reject a line item entirely when any nonzero bucket lacks its price.

- [ ] **Step 4: Run cost model tests and confirm GREEN**

Run: `swift test --filter CostModelsTests`

Expected: PASS.

- [ ] **Step 5: Write failing bundled catalog tests**

Assert catalog metadata is nonempty, every source URL is HTTPS and first-party, aliases resolve to one canonical entry, and the exact supported local fixture IDs resolve. Do not assert every possible upstream model.

- [ ] **Step 6: Run catalog tests and confirm RED**

Run: `swift test --filter PriceCatalogTests`

Expected: bundled resource is missing.

- [ ] **Step 7: Add reviewed JSON catalog and loader**

Configure `TokenLinkProviders` resources in `Package.swift`. Catalog version `2026-08-30.1` has effective date `2026-08-30` and these exact USD-per-million entries:

| Provider/model | Aliases | Input | Cache read | 5m write | 1h write | Output | Request modifier |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Codex `gpt-5.4` | `gpt-5.4-2026-03-05` | 2.50 | 0.25 | — | — | 15.00 | over 272,000 input: 2x input/cache and 1.5x output |
| Codex `gpt-5.5` | `gpt-5.5-2026-04-23` | 5.00 | 0.50 | — | — | 30.00 | over 272,000 input: 2x input/cache and 1.5x output |
| Claude `claude-sonnet-5` | none | 2.00 | 0.20 | 2.50 | 4.00 | 10.00 | none |
| Claude `claude-sonnet-4-6` | none | 3.00 | 0.30 | 3.75 | 6.00 | 15.00 | none |
| Claude `claude-opus-5` | none | 5.00 | 0.50 | 6.25 | 10.00 | 25.00 | none |
| Claude `claude-haiku-4-5-20251001` | `claude-haiku-4-5` | 1.00 | 0.10 | 1.25 | 2.00 | 5.00 | none |
| Kimi `kimi-k3` | `k3`, `kimi-code/k3` | 3.00 | 0.30 | 3.00 | — | 15.00 | none |

Each entry carries its exact official source URL: OpenAI model pages for GPT-5.4/5.5, Anthropic pricing/model pages for Claude, and `https://platform.kimi.ai/docs/pricing/chat-k3` for Kimi. Aliases are exact matches and never prefix-matched. A later upstream model remains visibly unpriced until a reviewed catalog change lands.

- [ ] **Step 8: Run core/provider catalog tests**

Run: `swift test --filter 'CostModelsTests|PriceCatalogTests'`

Expected: PASS.

- [ ] **Step 9: Commit Task 2**

```bash
git add Package.swift Sources/TokenLinkCore/CostModels.swift Sources/TokenLinkProviders/Costs/PriceCatalog.swift Sources/TokenLinkProviders/Resources/api-equivalent-prices.json Tests/TokenLinkCoreTests/CostModelsTests.swift Tests/TokenLinkProviderTests/PriceCatalogTests.swift
git commit -m "feat: add decimal API-equivalent price catalog"
```

### Task 3: OpenRouter and DeepSeek Authoritative Cost Providers

**Files:**
- Create: `Sources/TokenLinkProviders/Costs/AuthoritativeCostProvider.swift`
- Create: `Sources/TokenLinkProviders/Costs/OpenRouterCostProvider.swift`
- Create: `Sources/TokenLinkProviders/Costs/DeepSeekCostProvider.swift`
- Create: `Tests/TokenLinkProviderTests/AuthoritativeCostProviderTests.swift`
- Create: `Tests/TokenLinkProviderTests/Fixtures/openrouter-credits.json`
- Create: `Tests/TokenLinkProviderTests/Fixtures/openrouter-key.json`
- Create: `Tests/TokenLinkProviderTests/Fixtures/deepseek-balance.json`

**Interfaces:**
- Produces: `AuthoritativeCostProvider.fetch() async -> Result<AuthoritativeCostSnapshot, ProviderFailure>`.
- Produces: `AccountCostProvider(accountID:provider:)` for state-keyed coordination.
- Consumes: `HTTPClient`, `CredentialReader`, `EndpointPolicy`, `CurrencyAmount`, and `AuthoritativeCostSnapshot`.

- [ ] **Step 1: Write failing OpenRouter success and partial-success tests**

Use a URL-keyed actor fake returning complete official response shapes. Assert bearer auth and these literal results:

```swift
#expect(snapshot.balances == [
  AccountBalance(
    currency: "USD", available: Decimal(string: "74.5")!,
    purchased: Decimal(string: "100")!, used: Decimal(string: "25.5")!)
])
#expect(snapshot.periodSpend.first { $0.period == .weekly }?.amount.value == Decimal(string: "7.25"))
```

Make `/credits` 403 while `/key` succeeds and assert a usable snapshot plus `.partialSource("credits")`; reverse the failure and assert credits balance remains usable.

- [ ] **Step 2: Run OpenRouter tests and confirm RED**

Run: `swift test --filter OpenRouter`

Expected: compilation fails because the adapter is absent.

- [ ] **Step 3: Implement strict numeric decoding and independent endpoint merge**

Create a reusable `LosslessDecimal` decoder accepting JSON number or numeric string, rejecting booleans, empty strings, NaN, and infinity. Request exactly `https://openrouter.ai/api/v1/credits` and `/key` under an `EndpointPolicy(allowedHosts: ["openrouter.ai"])`. Return authentication only when no endpoint yielded usable data and authentication was the terminal cause.

- [ ] **Step 4: Run OpenRouter tests and confirm GREEN**

Run: `swift test --filter OpenRouter`

Expected: PASS.

- [ ] **Step 5: Write failing DeepSeek tests**

Cover CNY/USD balances, literal zero, `is_available: false`, string/number fields, malformed numeric data, 401, and policy validation. Assert currencies are separate and no spend is inferred.

- [ ] **Step 6: Run DeepSeek tests and confirm RED**

Run: `swift test --filter DeepSeek`

Expected: compilation fails because the adapter is absent.

- [ ] **Step 7: Implement DeepSeek adapter**

Request exactly `https://api.deepseek.com/user/balance`, retain `is_available`, map each `balance_infos` object independently, and report zero as valid. Use `EndpointPolicy(allowedHosts: ["api.deepseek.com"])` and the existing 20-second/redirect behavior through `HTTPClient`.

- [ ] **Step 8: Run authoritative provider suite**

Run: `swift test --filter AuthoritativeCostProviderTests`

Expected: PASS.

- [ ] **Step 9: Commit Task 3**

```bash
git add Sources/TokenLinkProviders/Costs Tests/TokenLinkProviderTests/AuthoritativeCostProviderTests.swift Tests/TokenLinkProviderTests/Fixtures/openrouter-credits.json Tests/TokenLinkProviderTests/Fixtures/openrouter-key.json Tests/TokenLinkProviderTests/Fixtures/deepseek-balance.json
git commit -m "feat: fetch authoritative provider balances"
```

### Task 4: Independent Cost Store, TTL, and Refresh Coalescing

**Files:**
- Create: `Sources/TokenLinkCore/CostStore.swift`
- Create: `Sources/TokenLinkApp/Costs/CostDashboardModel.swift`
- Create: `Tests/TokenLinkCoreTests/CostStoreTests.swift`
- Create: `Tests/TokenLinkAppTests/CostDashboardModelTests.swift`

**Interfaces:**
- Produces: `AuthoritativeCostState`, `EstimatedCostState`, and `CostStore` actor methods keyed by account UUID/provider.
- Produces: `CostDashboardModel.refreshCosts(force:)`, `loadIfNeeded()`, `disable()`, and immutable row projections.
- Consumes: closures `authoritativeLoader`, `estimateLoader`, and `now` so tests use real coordinator behavior without external I/O.

- [ ] **Step 1: Write failing last-known-good store tests**

Assert success replaces data, failure with no snapshot maps missing credentials/error, failure after success retains the exact snapshot and marks stale, and 15/30-minute aging is source-specific.

- [ ] **Step 2: Run store tests and confirm RED**

Run: `swift test --filter CostStoreTests`

Expected: compilation fails because store/state types are absent.

- [ ] **Step 3: Implement the actor store**

Use separate dictionaries `[UUID: AuthoritativeCostState]` and `[ProviderID: EstimatedCostState]`. Never serialize them. `accept` methods retain old snapshots on failure and never affect `ProviderStore`.

- [ ] **Step 4: Run store tests and confirm GREEN**

Run: `swift test --filter CostStoreTests`

Expected: PASS.

- [ ] **Step 5: Write failing dashboard lifecycle tests**

With counting async closures, assert disabled means zero calls; first page load calls each source once; a second load before TTL does not call; `force: true` calls again; concurrent refreshes coalesce; one failing source does not prevent another success; `disable()` cancels/clears presentation state.

- [ ] **Step 6: Run dashboard tests and confirm RED**

Run: `swift test --filter CostDashboardModelTests`

Expected: compilation fails because the dashboard model is absent.

- [ ] **Step 7: Implement dashboard coordination**

Make it `@MainActor @Observable`, retain one `Task<Void, Never>?` for the aggregate refresh, perform source loads in a task group, consult snapshot timestamps for TTL, and call `CostStore` independently per result. Expose cost phase metadata without amounts for diagnostics.

- [ ] **Step 8: Run dashboard tests and confirm GREEN**

Run: `swift test --filter CostDashboardModelTests`

Expected: PASS.

- [ ] **Step 9: Commit Task 4**

```bash
git add Sources/TokenLinkCore/CostStore.swift Sources/TokenLinkApp/Costs/CostDashboardModel.swift Tests/TokenLinkCoreTests/CostStoreTests.swift Tests/TokenLinkAppTests/CostDashboardModelTests.swift
git commit -m "feat: coordinate cost refresh independently"
```

### Task 5: Bounded Streaming JSONL Reader

**Files:**
- Create: `Sources/TokenLinkApp/LocalUsage/JSONLStreamingReader.swift`
- Modify: `Sources/TokenLinkApp/LocalUsage/LocalUsageObserver.swift`
- Create: `Tests/TokenLinkAppTests/JSONLStreamingReaderTests.swift`

**Interfaces:**
- Produces: `JSONLStreamingReader.read(url:onRecord:) throws -> JSONLReadReport`.
- Produces: constants `chunkBytes = 65_536`, `maximumRecordBytes = 1_048_576`, and observer `maximumFileBytes = 268_435_456`.
- Consumes: a synchronous record closure; does not retain raw lines after delivery.

- [ ] **Step 1: Write failing boundary tests**

Create temporary files and assert: records split at every chunk boundary arrive intact; final record without newline arrives; exactly 1 MiB is delivered; 1 MiB plus one byte is skipped and counted; cancellation throws; and exactly/over 256 MiB observer files are processed/skipped. Expected values are literal record byte counts.

- [ ] **Step 2: Run reader tests and confirm RED**

Run: `swift test --filter JSONLStreamingReaderTests`

Expected: compilation fails because the reader is absent.

- [ ] **Step 3: Implement chunked FileHandle reading**

Read at most 65,536 bytes per call, maintain only the incomplete current record, discard an oversized record until its newline, check `Task.checkCancellation()` between chunks and records, and close the handle with `defer`. Do not use `Data(contentsOf:)` in production local scanning.

- [ ] **Step 4: Run reader tests and confirm GREEN**

Run: `swift test --filter JSONLStreamingReaderTests`

Expected: PASS.

- [ ] **Step 5: Refactor observer to sequential path-sorted streaming**

Sort enumerated `.jsonl` URLs by standardized path, check mtime/size before opening, stream each file fully before the next, sanitize warnings to counts, and retain no event arrays or paths.

- [ ] **Step 6: Run existing local usage tests**

Run: `swift test --filter LocalUsageTests`

Expected: PASS with the observer now using the streaming reader.

- [ ] **Step 7: Commit Task 5**

```bash
git add Sources/TokenLinkApp/LocalUsage/JSONLStreamingReader.swift Sources/TokenLinkApp/LocalUsage/LocalUsageObserver.swift Tests/TokenLinkAppTests/JSONLStreamingReaderTests.swift Tests/TokenLinkAppTests/LocalUsageTests.swift
git commit -m "perf: stream local usage records with hard bounds"
```

### Task 6: Model-Aware Codex, Claude, and Kimi Cost Estimation

**Files:**
- Modify: `Sources/TokenLinkApp/LocalUsage/LocalUsageModels.swift`
- Modify: `Sources/TokenLinkApp/LocalUsage/LocalUsageReaders.swift`
- Modify: `Sources/TokenLinkApp/LocalUsage/LocalUsageObserver.swift`
- Create: `Sources/TokenLinkApp/Costs/LocalCostEstimator.swift`
- Modify: `Tests/TokenLinkAppTests/LocalUsageTests.swift`
- Create: `Tests/TokenLinkAppTests/LocalCostEstimatorTests.swift`

**Interfaces:**
- Produces: stateful `LocalUsageRecordParser.consume(_:) -> NormalizedModelUsage?` and `finish()` behavior per file.
- Produces: `LocalCostEstimator.estimate(provider:since:through:) -> EstimatedCostSnapshot`.
- Consumes: `JSONLStreamingReader` and `PriceCatalog`.

- [ ] **Step 1: Write failing parser behavior tests**

Use complete stripped JSONL fixtures and assert literal buckets/model IDs for:

- Codex turn-context model changes, cached input subtraction, repeated cumulative totals, and a child rollout marker that must not charge replayed parent totals.
- Claude input/cache-read/cache-creation/output mapping and duplicate message IDs.
- Kimi top-level model plus `inputOther`, `inputCacheRead`, `inputCacheCreation`, and output mapping.

Before each test body, name the mutation it catches in a code comment, such as `// Catches charging cached input twice.`

- [ ] **Step 2: Run parser tests and confirm RED**

Run: `swift test --filter 'CodexCost|ClaudeCost|KimiCost'`

Expected: assertions fail because current events do not preserve model or four buckets.

- [ ] **Step 3: Implement stateful record parsers**

Decode only timestamp, type, model, token counters, message/event IDs, and ancestry markers. Codex computes deltas from cumulative counters and resets state safely when counters decrease; cached input is subtracted from total input. Claude treats cache buckets separately and deduplicates nonempty message IDs. Kimi maps all four source fields directly.

- [ ] **Step 4: Run parser tests and confirm GREEN**

Run: `swift test --filter 'CodexCost|ClaudeCost|KimiCost'`

Expected: PASS.

- [ ] **Step 5: Write failing estimator tests**

Inject a literal test catalog and temporary records. Assert a seven-day interval, per-model line items, Decimal per-currency totals, unknown-model exclusion, five-minute cache-write fallback warning, catalog metadata, and no prompt/response retention.

- [ ] **Step 6: Run estimator tests and confirm RED**

Run: `swift test --filter LocalCostEstimatorTests`

Expected: compilation fails because the estimator is absent.

- [ ] **Step 7: Implement streaming aggregation and pricing**

Price each normalized event as it arrives so request-level long-context modifiers remain correct, then aggregate priced line items by provider/model/currency. Keep only a nonempty dedupe-ID set and accumulator dictionaries. Create `EstimatedCostSnapshot` with exact window/catalog timestamps.

- [ ] **Step 8: Run local suites and confirm GREEN**

Run: `swift test --filter 'LocalUsageTests|LocalCostEstimatorTests|JSONLStreamingReaderTests'`

Expected: PASS.

- [ ] **Step 9: Commit Task 6**

```bash
git add Sources/TokenLinkApp/LocalUsage Sources/TokenLinkApp/Costs/LocalCostEstimator.swift Tests/TokenLinkAppTests/LocalUsageTests.swift Tests/TokenLinkAppTests/LocalCostEstimatorTests.swift
git commit -m "feat: estimate local API-equivalent model costs"
```

### Task 7: App Composition, Cost Accounts, and Quota Isolation

**Files:**
- Modify: `Sources/TokenLinkApp/AppModel.swift`
- Modify: `Sources/TokenLinkApp/KeychainVault.swift`
- Modify: `Sources/TokenLinkApp/Views/ProvidersView.swift`
- Modify: `Sources/TokenLinkApp/Views/WatchFaceSettingsView.swift`
- Modify: `Tests/TokenLinkAppTests/AppModelTests.swift`
- Modify: `Tests/TokenLinkAppTests/KeychainVaultTests.swift`

**Interfaces:**
- Produces: `AppModel.costDashboard`, `setBetaCostsEnabled(_:)`, `refreshCosts(force:)`, and fixed metric setter.
- Produces: live construction of `OpenRouterCostProvider`, `DeepSeekCostProvider`, and three `LocalCostEstimator` sources.
- Consumes: cost account credentials using existing provider-plus-UUID Keychain names.

- [ ] **Step 1: Write failing quota-isolation tests**

Create configuration containing enabled OpenRouter/DeepSeek accounts. Assert `orderedProviderRows`, `accountGroups` used by quota overview, watch-enabled providers, watch payload candidates, and quota refresher inputs exclude them. Assert setting beta false results in zero cost loader calls even through `start()` and manual quota refresh.

- [ ] **Step 2: Run isolation tests and confirm RED**

Run: `swift test --filter 'costOnlyProvidersNeverEnterQuota|disabledCostsStartNoWork'`

Expected: failures because enumeration still relies on all provider IDs.

- [ ] **Step 3: Implement capability filtering and cost composition**

Filter all quota/watch code using `.quota`; keep cost accounts in configuration and credential state; build authoritative cost bindings only for enabled cost accounts; build local estimators by local-cost capability. Do not invoke cost refresh from `start()`, scheduler, wake, network restoration, quota manual refresh, or watch commands.

- [ ] **Step 4: Run isolation tests and confirm GREEN**

Run: `swift test --filter 'costOnlyProvidersNeverEnterQuota|disabledCostsStartNoWork'`

Expected: PASS.

- [ ] **Step 5: Write failing enablement/account/Keychain tests**

Assert enabling beta selects `.localEstimate(.codex)` when selection is `.none`; disabling clears in-memory cost presentation and leaves credentials intact; OpenRouter/DeepSeek account keys use default and UUID-namespaced Keychain accounts; provider removal deletes/promotes keys with existing semantics.

- [ ] **Step 6: Run focused tests and confirm RED**

Run: `swift test --filter 'betaCosts|costAccount|Keychain'`

Expected: missing setters/live construction or wrong filtering.

- [ ] **Step 7: Implement AppModel actions and provider controls**

Add beta setters, explicit `refreshCosts(force:)`, route-load method, metric setter, and cost account creation. In Providers, show quota providers as before and a separate beta-cost section for OpenRouter/DeepSeek with explicit Management/API Key help text.

- [ ] **Step 8: Run app/keychain tests**

Run: `swift test --filter 'AppModelTests|KeychainVaultTests|ConfigurationStoreTests'`

Expected: PASS.

- [ ] **Step 9: Commit Task 7**

```bash
git add Sources/TokenLinkApp/AppModel.swift Sources/TokenLinkApp/KeychainVault.swift Sources/TokenLinkApp/Views/ProvidersView.swift Sources/TokenLinkApp/Views/WatchFaceSettingsView.swift Tests/TokenLinkAppTests/AppModelTests.swift Tests/TokenLinkAppTests/KeychainVaultTests.swift
git commit -m "feat: compose cost sources without quota coupling"
```

### Task 8: Costs Beta UI, Menu-Bar Supplement, Localization, and Diagnostics

**Files:**
- Create: `Sources/TokenLinkApp/Views/CostsView.swift`
- Modify: `Sources/TokenLinkApp/Views/ControlCenterView.swift`
- Modify: `Sources/TokenLinkApp/Views/MenuBarView.swift`
- Modify: `Sources/TokenLinkApp/Views/SettingsView.swift`
- Modify: `Sources/TokenLinkApp/Strings.swift`
- Modify: `Sources/TokenLinkApp/AppModel.swift`
- Modify: `Sources/TokenLinkApp/DiagnosticExporter.swift`
- Modify: `Tests/TokenLinkAppTests/AppModelTests.swift`
- Modify: `Tests/TokenLinkAppTests/LocalizationTests.swift`

**Interfaces:**
- Produces: Costs route/load behavior, dedicated refresh button, source cards, menu supplement formatter, and fixed metric picker.
- Consumes: cost dashboard row projections; UI never recomputes money.

- [ ] **Step 1: Write failing menu-label and diagnostics tests**

Assert literal labels:

```swift
#expect(model.menuBarLabel == "Codex 42% · ≈$8.31/7d")
#expect(authoritativeModel.menuBarLabel == "Codex 42% · OR $18.40 left")
#expect(missingSelectionModel.menuBarLabel == "Codex 42%")
```

Assert the quota provider still determines the first segment and severity input. Serialize diagnostics and assert it contains beta state, source kind, phase, catalog version, error category, and refresh time while excluding literal fixture amounts, account labels/UUIDs, model totals, and paths.

- [ ] **Step 2: Run focused label/diagnostic tests and confirm RED**

Run: `swift test --filter 'menuBarCost|costDiagnostics'`

Expected: label lacks supplement and diagnostics lack sanitized metadata.

- [ ] **Step 3: Implement formatting and redacted diagnostics**

Use `NumberFormatter`/currency code for display only. Estimated supplement always begins with `≈`; authoritative supplement never does. A missing selected row returns nil supplement. Diagnostics receive only `CostDiagnosticMetadata`, never snapshots.

- [ ] **Step 4: Run label/diagnostic tests and confirm GREEN**

Run: `swift test --filter 'menuBarCost|costDiagnostics'`

Expected: PASS.

- [ ] **Step 5: Add Costs route, cards, settings, and three-language keys**

Insert `.costs` between Providers and StopWatch. `CostsView.task` calls load only when enabled; its toolbar calls `refreshCosts(force: true)`. Show separate authoritative/estimated sections and the exact `Estimated/API-equivalent` label, period, effective date, freshness, provenance, warning, stale, and failure details. Settings controls beta and a fixed metric; no rotating selection.

- [ ] **Step 6: Run build and localization tests**

Run: `swift build && swift test --filter LocalizationTests`

Expected: PASS with exhaustive three-language coverage.

- [ ] **Step 7: Inspect SwiftUI previews/build warnings and refactor**

Run: `swift build 2>&1 | tee /tmp/tokenlink-cost-build.log`

Expected: exit 0 and no new warning lines referring to cost files.

- [ ] **Step 8: Commit Task 8**

```bash
git add Sources/TokenLinkApp/Views/CostsView.swift Sources/TokenLinkApp/Views/ControlCenterView.swift Sources/TokenLinkApp/Views/MenuBarView.swift Sources/TokenLinkApp/Views/SettingsView.swift Sources/TokenLinkApp/Strings.swift Sources/TokenLinkApp/AppModel.swift Sources/TokenLinkApp/DiagnosticExporter.swift Tests/TokenLinkAppTests/AppModelTests.swift Tests/TokenLinkAppTests/LocalizationTests.swift
git commit -m "feat: present cost beta with explicit provenance"
```

### Task 9: Resource Budgets, Privacy Gate, and Full Verification

**Files:**
- Create: `scripts/resource_check.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/privacy_scan.sh`
- Create: `Tests/TokenLinkAppTests/LocalCostResourceTests.swift`
- Modify: `README.md`

**Interfaces:**
- Produces: reproducible local/CI resource gate and public beta documentation.
- Consumes: already-built test bundle and release executable; measurement excludes compiler processes.

- [ ] **Step 1: Write failing resource workload test**

Generate a deterministic 64 MiB JSONL file from repeated stripped usage records, stream it through the real reader/aggregator, and assert literal event/token totals so an empty scan cannot satisfy the gate. Skip only when `TOKENLINK_RESOURCE_WORKLOAD` is not `1`.

- [ ] **Step 2: Run workload test and confirm RED**

Run: `TOKENLINK_RESOURCE_WORKLOAD=1 swift test --filter LocalCostResourceTests`

Expected: fails until the workload helper and expected aggregation are complete.

- [ ] **Step 3: Complete workload and confirm functional GREEN**

Run: `TOKENLINK_RESOURCE_WORKLOAD=1 swift test --filter LocalCostResourceTests`

Expected: PASS with expected aggregate counts.

- [ ] **Step 4: Implement executable resource gate**

`scripts/resource_check.sh` must:

1. run `swift build -c release` and `swift test --build-tests` before measurement;
2. run the filtered workload under `/usr/bin/time -l` with `--skip-build`;
3. parse maximum RSS bytes and fail above `167772160`;
4. measure elapsed seconds and fail above `30`;
5. measure `.build/release/tokenlink` bytes and fail above `15728640`;
6. print only sizes/times/status, never paths or monetary data.

- [ ] **Step 5: Run resource gate and confirm thresholds**

Run: `bash scripts/resource_check.sh`

Expected: PASS under all three limits.

- [ ] **Step 6: Extend privacy scan and CI workflow**

Make privacy scan reject production logging/interpolation of `balance`, `amount.value`, authorization headers, raw bodies, and transcript paths while allowing domain declarations. Add a macOS CI job that runs `bash scripts/resource_check.sh` after the regular test job.

- [ ] **Step 7: Document the beta accurately**

README must distinguish authoritative balance from local `Estimated/API-equivalent`, state that subscription value is not estimated, explain OpenRouter Management Key partial behavior, DeepSeek multi-currency behavior, local directories, no telemetry/persistence, and the resource limits.

- [ ] **Step 8: Run fresh full verification**

Run exactly:

```bash
swift build
bash scripts/test.sh
swift format lint --strict Package.swift
swift format lint --recursive --strict Sources Tests
bash scripts/privacy_scan.sh
bash scripts/resource_check.sh
git diff --check
```

Expected: every command exits 0; test count is greater than the 162-test baseline; privacy/resource gates print PASS.

- [ ] **Step 9: Review the mutation checklist**

Confirm tests fail for a wrong cost rate, wrong currency grouping, omitted estimate marker, treating a cost-only provider as quota, following a redirect, accepting malformed decimals, loading while disabled, ignoring TTL, retaining a whole file, accepting a 1 MiB-plus-one record, and exporting a fixture amount.

- [ ] **Step 10: Commit Task 9**

```bash
git add scripts/resource_check.sh scripts/privacy_scan.sh .github/workflows/ci.yml Tests/TokenLinkAppTests/LocalCostResourceTests.swift README.md
git commit -m "ci: enforce cost privacy and resource budgets"
```

- [ ] **Step 11: Request code review before integration**

Use `superpowers:requesting-code-review` against the complete branch diff from `6342486` through HEAD. Resolve findings with one RED/GREEN cycle per bug, then rerun the complete verification block before claiming completion.
