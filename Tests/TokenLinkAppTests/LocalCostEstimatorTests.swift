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
  #expect(snapshot.lineItems[0].components.map(\.amount.value) == [1, 2, 3, 4])
  #expect(snapshot.lineItems[0].price?.sourceURL.absoluteString == "https://example.com/claude")
  #expect(snapshot.lineItems[0].requestCount == 1)
  #expect(snapshot.lineItems[0].warnings == [.assumedFiveMinuteCacheWrite])
  #expect(snapshot.totals == [CurrencyAmount(value: 10, currency: "USD")])
  #expect(snapshot.unknownModelIDs == ["unknown-claude"])
  let presentation = String(describing: snapshot)
  #expect(!presentation.contains("must-not-survive"))
  #expect(!presentation.contains("also-private"))
  #expect(!presentation.contains("duplicate-private"))
  #expect(!presentation.contains("m1"))
}

@Test func codexEstimateMatchesRequestLevelCommunityFormula() throws {
  // Catches double charging cached input, reasoning output, or Fast/long-context tiers.
  let root = try temporaryCostHome()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appending(
    path: ".codex/sessions/2026/08/31",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("service_tier = \"priority\"\n".utf8).write(
    to: root.appending(path: ".codex/config.toml"))
  try Data(
    """
    {"timestamp":"2026-08-31T00:00:00Z","type":"session_meta","payload":{"thread_source":"user"}}
    {"timestamp":"2026-08-31T00:00:01Z","type":"turn_context","payload":{"model":"gpt-5.6"}}
    {"timestamp":"2026-08-31T00:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900000,"cached_input_tokens":300000,"cache_write_input_tokens":60000,"output_tokens":30000},"last_token_usage":{"input_tokens":300000,"cached_input_tokens":100000,"cache_write_input_tokens":20000,"output_tokens":10000,"reasoning_output_tokens":4000}}}}

    """.utf8
  ).write(to: directory.appending(path: "rollout.jsonl"))

  let through = Date(timeIntervalSince1970: 1_788_220_800)
  let catalog = PriceCatalog(
    version: "community-formula",
    effectiveDate: through,
    entries: [
      ModelPrice(
        provider: .codex,
        modelID: "gpt-5.6-sol",
        aliases: ["gpt-5.6"],
        currency: "USD",
        uncachedInputPerMillion: 4,
        cacheReadPerMillion: Decimal(string: "0.4"),
        cacheWritePerMillion: 5,
        outputPerMillion: 20,
        fastMultiplier: 2,
        sourceURL: URL(string: "https://developers.openai.com/api/docs/pricing")!,
        longContext: LongContextPricing(
          thresholdInputTokens: 272_000,
          inputMultiplier: 2,
          outputMultiplier: Decimal(string: "1.5")!))
    ])
  let snapshot = try LocalCostEstimator(
    observer: LocalUsageObserver(homeURL: root),
    catalog: catalog,
    now: { through }
  ).estimate(
    provider: .codex,
    since: through.addingTimeInterval(-604_800),
    through: through)

  let item = try #require(snapshot.lineItems.first)
  #expect(snapshot.lineItems.count == 1)
  #expect(item.usage.modelID == "gpt-5.6-sol")
  #expect(item.usage.uncachedInputTokens == 180_000)
  #expect(item.usage.cacheReadTokens == 100_000)
  #expect(item.usage.cacheWriteTokens == 20_000)
  #expect(item.usage.outputTokens == 10_000)
  #expect(item.requestCount == 1)
  #expect(item.longContextRequestCount == 1)
  #expect(item.fastRequestCount == 1)
  #expect(
    item.components.map(\.amount.value) == [
      Decimal(string: "2.88"),
      Decimal(string: "0.16"),
      Decimal(string: "0.4"),
      Decimal(string: "0.6"),
    ])
  #expect(item.amount.value == Decimal(string: "4.04"))
  #expect(snapshot.totals == [CurrencyAmount(value: Decimal(string: "4.04")!, currency: "USD")])
  #expect(snapshot.unknownModelIDs.isEmpty)
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
  let shortContext = try #require(
    snapshot.lineItems.first { $0.usage.modelID == "short-context" })
  #expect(shortContext.requestCount == 2)
  #expect(shortContext.longContextRequestCount == 0)
  #expect(shortContext.components.first?.tokens == 1_200)
  #expect(shortContext.components.first?.effectiveRatePerMillion == 1)
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

@Test func localCostEstimatorBuildsAllDisplayPeriodsFromOneBoundedResult() throws {
  let root = try temporaryCostHome()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appending(
    path: ".kimi-code/sessions/project/session/agents/agent",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let through = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 18)))
  let today = through.addingTimeInterval(-2 * 3_600)
  let week = through.addingTimeInterval(-3 * 86_400)
  let month = through.addingTimeInterval(-20 * 86_400)
  try Data(
    """
    {"type":"usage.record","time":\(Int(today.timeIntervalSince1970 * 1_000)),"model":"priced","usage":{"inputOther":1000000,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}
    {"type":"usage.record","time":\(Int(week.timeIntervalSince1970 * 1_000)),"model":"priced","usage":{"inputOther":1000000,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}
    {"type":"usage.record","time":\(Int(month.timeIntervalSince1970 * 1_000)),"model":"priced","usage":{"inputOther":1000000,"inputCacheRead":0,"inputCacheCreation":0,"output":0}}

    """.utf8
  ).write(to: directory.appending(path: "periods.jsonl"))

  let catalog = PriceCatalog(
    version: "period-test",
    effectiveDate: month,
    entries: [
      ModelPrice(
        provider: .kimi,
        modelID: "priced",
        aliases: [],
        currency: "USD",
        uncachedInputPerMillion: 1,
        cacheReadPerMillion: nil,
        outputPerMillion: nil,
        sourceURL: URL(string: "https://example.com/kimi")!)
    ])
  let periods = try LocalCostEstimator(
    observer: LocalUsageObserver(homeURL: root),
    catalog: catalog,
    now: { through }
  ).estimatePeriods(provider: .kimi, through: through, calendar: calendar)

  #expect(periods.snapshots[.today]?.totals.first?.value == 1)
  #expect(periods.snapshots[.week]?.totals.first?.value == 2)
  #expect(periods.snapshots[.month]?.totals.first?.value == 3)
  #expect(
    periods.snapshots[.today]?.period
      == CostDisplayPeriod.today.interval(endingAt: through, calendar: calendar))
  #expect(
    periods.snapshots[.month]?.period
      == CostDisplayPeriod.month.interval(endingAt: through, calendar: calendar))
}

private func temporaryCostHome() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
