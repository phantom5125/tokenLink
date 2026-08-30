import Foundation
import Testing
import TokenLinkCore
import TokenLinkProviders

@testable import TokenLinkApp

@Test func localCostEstimatorBuildsSevenDayClaudeEstimateWithoutContentRetention() throws {
  // Catches duplicate charging, partial pricing, or retaining transcript content/IDs.
  let root = try temporaryCostHome()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appending(
    path: ".claude/projects/project",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data(
    """
    {"timestamp":"2026-08-29T12:00:00Z","type":"assistant","message":{"id":"m1","model":"priced-claude","content":"must-not-survive","usage":{"input_tokens":1000000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":1000000,"output_tokens":1000000}}}
    {"timestamp":"2026-08-29T12:01:00Z","type":"assistant","message":{"id":"m-unknown","model":"unknown-claude","content":"also-private","usage":{"input_tokens":1000000,"output_tokens":1000000}}}

    """.utf8
  ).write(to: directory.appending(path: "a.jsonl"))
  try Data(
    """
    {"timestamp":"2026-08-29T12:00:00Z","type":"assistant","message":{"id":"m1","model":"priced-claude","content":"duplicate-private","usage":{"input_tokens":1000000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":1000000,"output_tokens":1000000}}}

    """.utf8
  ).write(to: directory.appending(path: "b.jsonl"))

  let through = Date(timeIntervalSince1970: 1_788_134_400)
  let since = through.addingTimeInterval(-604_800)
  let effective = Date(timeIntervalSince1970: 1_787_961_600)
  let catalog = PriceCatalog(
    version: "test-catalog",
    effectiveDate: effective,
    entries: [
      ModelPrice(
        provider: .claude,
        modelID: "priced-claude",
        aliases: [],
        currency: "USD",
        uncachedInputPerMillion: 1,
        cacheReadPerMillion: 2,
        cacheWriteFiveMinutePerMillion: 3,
        outputPerMillion: 4,
        sourceURL: URL(string: "https://example.com/claude")!)
    ])
  let scannedAt = through.addingTimeInterval(60)
  let estimator = LocalCostEstimator(
    observer: LocalUsageObserver(homeURL: root),
    catalog: catalog,
    now: { scannedAt })

  let snapshot = try estimator.estimate(
    provider: .claude,
    since: since,
    through: through)

  #expect(snapshot.period == DateInterval(start: since, end: through))
  #expect(snapshot.catalogVersion == "test-catalog")
  #expect(snapshot.catalogEffectiveDate == effective)
  #expect(snapshot.scannedAt == scannedAt)
  #expect(snapshot.lineItems.count == 1)
  #expect(snapshot.lineItems[0].usage.modelID == "priced-claude")
  #expect(snapshot.lineItems[0].usage.deduplicationKey.isEmpty)
  #expect(snapshot.lineItems[0].amount == CurrencyAmount(value: 10, currency: "USD"))
  #expect(snapshot.lineItems[0].warnings == [.assumedFiveMinuteCacheWrite])
  #expect(snapshot.totals == [CurrencyAmount(value: 10, currency: "USD")])
  #expect(snapshot.unknownModelIDs == ["unknown-claude"])
  let presentation = String(describing: snapshot)
  #expect(!presentation.contains("must-not-survive"))
  #expect(!presentation.contains("also-private"))
  #expect(!presentation.contains("duplicate-private"))
  #expect(!presentation.contains("m1"))
}

@Test func localCostEstimatorPricesBeforeAggregationAndKeepsCurrenciesSeparate() throws {
  // Catches applying long-context multipliers to an aggregated seven-day token count.
  let root = try temporaryCostHome()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appending(
    path: ".kimi-code/sessions/project/session/agents/agent",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data(
    """
    {"type":"usage.record","time":1788048000000,"model":"short-context","usage":{"inputOther":600,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}
    {"type":"usage.record","time":1788048060000,"model":"short-context","usage":{"inputOther":600,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}
    {"type":"usage.record","time":1788048120000,"model":"euro-model","usage":{"inputOther":1000000,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}

    """.utf8
  ).write(to: directory.appending(path: "wire.jsonl"))

  let through = Date(timeIntervalSince1970: 1_788_134_400)
  let since = through.addingTimeInterval(-604_800)
  let catalog = PriceCatalog(
    version: "request-pricing",
    effectiveDate: since,
    entries: [
      ModelPrice(
        provider: .kimi,
        modelID: "short-context",
        aliases: [],
        currency: "USD",
        uncachedInputPerMillion: 1,
        cacheReadPerMillion: nil,
        outputPerMillion: nil,
        sourceURL: URL(string: "https://example.com/usd")!,
        longContext: LongContextPricing(
          thresholdInputTokens: 1_000,
          inputMultiplier: 2,
          outputMultiplier: 1)),
      ModelPrice(
        provider: .kimi,
        modelID: "euro-model",
        aliases: [],
        currency: "EUR",
        uncachedInputPerMillion: 2,
        cacheReadPerMillion: nil,
        outputPerMillion: nil,
        sourceURL: URL(string: "https://example.com/eur")!),
    ])
  let estimator = LocalCostEstimator(
    observer: LocalUsageObserver(homeURL: root),
    catalog: catalog,
    now: { through })

  let snapshot = try estimator.estimate(
    provider: .kimi,
    since: since,
    through: through)

  #expect(snapshot.lineItems.map(\.usage.modelID) == ["euro-model", "short-context"])
  #expect(
    snapshot.lineItems.first { $0.usage.modelID == "short-context" }?.amount.value
      == Decimal(string: "0.0012"))
  #expect(
    snapshot.totals == [
      CurrencyAmount(value: 2, currency: "EUR"),
      CurrencyAmount(value: Decimal(string: "0.0012")!, currency: "USD"),
    ])
}

@Test func localCostEstimatorSkipsCountersThatOverflowAnAggregate() throws {
  // Catches repeated attacker-controlled Int.max counters trapping the local scanner.
  let root = try temporaryCostHome()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appending(
    path: ".kimi-code/sessions/project/session/agents/agent",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data(
    """
    {"type":"usage.record","time":1788048000000,"model":"huge","usage":{"inputOther":9223372036854775807,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}
    {"type":"usage.record","time":1788048060000,"model":"huge","usage":{"inputOther":9223372036854775807,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}

    """.utf8
  ).write(to: directory.appending(path: "wire.jsonl"))

  let through = Date(timeIntervalSince1970: 1_788_134_400)
  let catalog = PriceCatalog(
    version: "overflow-test",
    effectiveDate: through,
    entries: [
      ModelPrice(
        provider: .kimi,
        modelID: "huge",
        aliases: [],
        currency: "USD",
        uncachedInputPerMillion: 1,
        cacheReadPerMillion: nil,
        outputPerMillion: nil,
        sourceURL: URL(string: "https://example.com/huge")!)
    ])
  let snapshot = try LocalCostEstimator(
    observer: LocalUsageObserver(homeURL: root),
    catalog: catalog,
    now: { through }
  ).estimate(
    provider: .kimi,
    since: through.addingTimeInterval(-604_800),
    through: through)

  #expect(snapshot.lineItems.first?.usage.uncachedInputTokens == Int.max)
  #expect(snapshot.warnings.contains(.invalidTokenCount))
}

private func temporaryCostHome() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
