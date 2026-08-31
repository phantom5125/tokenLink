import Foundation
import Testing

@testable import TokenLinkCore

private let sourceURL = URL(string: "https://example.com/pricing")!

@Test func costDisplayPeriodsUseLocalCalendarDayAndTrailingWindows() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 3_600))
  let through = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 18)))

  #expect(
    CostDisplayPeriod.today.interval(endingAt: through, calendar: calendar).start
      == calendar.startOfDay(for: through))
  #expect(
    CostDisplayPeriod.week.interval(endingAt: through, calendar: calendar).start
      == calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: through)))
  #expect(
    CostDisplayPeriod.month.interval(endingAt: through, calendar: calendar).start
      == calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: through)))
}

@Test func priceCalculationUsesFourIndependentBuckets() throws {
  // Catches dropping or double-charging any cache/input/output bucket.
  let usage = NormalizedModelUsage(
    provider: .claude,
    modelID: "claude-sonnet-4-6",
    timestamp: Date(timeIntervalSince1970: 1),
    uncachedInputTokens: 1_000_000,
    cacheReadTokens: 1_000_000,
    cacheWriteTokens: 1_000_000,
    outputTokens: 1_000_000,
    deduplicationKey: "m1")
  let price = ModelPrice(
    provider: .claude,
    modelID: "claude-sonnet-4-6",
    aliases: [],
    currency: "USD",
    uncachedInputPerMillion: 3,
    cacheReadPerMillion: Decimal(string: "0.3"),
    cacheWriteFiveMinutePerMillion: Decimal(string: "3.75"),
    cacheWriteOneHourPerMillion: 6,
    outputPerMillion: 15,
    sourceURL: sourceURL)

  let item = try #require(CostCalculator.lineItem(usage: usage, price: price))

  #expect(item.amount == CurrencyAmount(value: Decimal(string: "22.05")!, currency: "USD"))
  #expect(item.components.map(\.category) == CostComponentCategory.allCases)
  #expect(item.components.map(\.amount.value) == [3, Decimal(string: "0.3")!, 3.75, 15])
  #expect(item.components.map(\.effectiveRatePerMillion) == [3, Decimal(string: "0.3"), 3.75, 15])
  #expect(item.price == price)
  #expect(item.requestCount == 1)
  #expect(item.longContextRequestCount == 0)
  #expect(item.warnings == [.assumedFiveMinuteCacheWrite])
}

@Test func priceCalculationAppliesLongContextPerRequest() throws {
  // Catches applying the >272K multiplier to a seven-day aggregate or at the boundary itself.
  let price = ModelPrice(
    provider: .codex,
    modelID: "gpt-5.5",
    aliases: [],
    currency: "usd",
    uncachedInputPerMillion: 5,
    cacheReadPerMillion: Decimal(string: "0.5"),
    outputPerMillion: 30,
    sourceURL: sourceURL,
    longContext: LongContextPricing(
      thresholdInputTokens: 272_000,
      inputMultiplier: 2,
      outputMultiplier: Decimal(string: "1.5")!))
  let atBoundary = NormalizedModelUsage(
    provider: .codex,
    modelID: "gpt-5.5",
    timestamp: .distantPast,
    uncachedInputTokens: 272_000,
    outputTokens: 1_000_000)
  let overBoundary = NormalizedModelUsage(
    provider: .codex,
    modelID: "gpt-5.5",
    timestamp: .distantPast,
    uncachedInputTokens: 272_001,
    outputTokens: 1_000_000)

  #expect(
    try #require(CostCalculator.lineItem(usage: atBoundary, price: price)).amount.value
      == Decimal(string: "31.36"))
  let longItem = try #require(CostCalculator.lineItem(usage: overBoundary, price: price))
  #expect(longItem.amount.value == Decimal(string: "47.72001"))
  #expect(longItem.longContextRequestCount == 1)
  #expect(
    longItem.components.first { $0.category == .uncachedInput }?.effectiveRatePerMillion == 10)
  #expect(longItem.components.first { $0.category == .output }?.effectiveRatePerMillion == 45)
}

@Test func codexPriceCalculationUsesCacheWriteAndFastRatesWithoutDoubleCounting() throws {
  // Codex input categories arrive as disjoint normalized buckets. Fast is an
  // independent processing multiplier over the selected context tier.
  let usage = NormalizedModelUsage(
    provider: .codex,
    modelID: "gpt-5.6-sol",
    timestamp: .distantPast,
    uncachedInputTokens: 1_000_000,
    cacheReadTokens: 1_000_000,
    cacheWriteTokens: 1_000_000,
    outputTokens: 1_000_000,
    processingTier: .fast)
  let price = ModelPrice(
    provider: .codex,
    modelID: "gpt-5.6-sol",
    aliases: ["gpt-5.6"],
    currency: "USD",
    uncachedInputPerMillion: 4,
    cacheReadPerMillion: Decimal(string: "0.4"),
    cacheWritePerMillion: 5,
    outputPerMillion: 20,
    fastMultiplier: 2,
    sourceURL: sourceURL)

  let item = try #require(CostCalculator.lineItem(usage: usage, price: price))

  #expect(item.amount.value == Decimal(string: "58.8"))
  #expect(item.components.map(\.amount.value) == [8, Decimal(string: "0.8")!, 10, 40])
  #expect(item.fastRequestCount == 1)
  #expect(item.warnings.isEmpty)
}

@Test func fastUsageFallsBackToReviewedStandardRateWithWarning() throws {
  let usage = NormalizedModelUsage(
    provider: .codex,
    modelID: "legacy",
    timestamp: .distantPast,
    uncachedInputTokens: 1_000_000,
    processingTier: .fast)
  let price = ModelPrice(
    provider: .codex,
    modelID: "legacy",
    aliases: [],
    currency: "USD",
    uncachedInputPerMillion: 3,
    cacheReadPerMillion: nil,
    outputPerMillion: nil,
    sourceURL: sourceURL)

  let item = try #require(CostCalculator.lineItem(usage: usage, price: price))

  #expect(item.amount.value == 3)
  #expect(item.fastRequestCount == 1)
  #expect(item.warnings == [.fastRateUnavailable])
}

@Test func normalizedUsageSaturatesTotalInputInsteadOfOverflowing() {
  // Catches malicious transcript counters trapping before long-context pricing.
  let usage = NormalizedModelUsage(
    provider: .kimi,
    modelID: "huge",
    timestamp: .distantPast,
    uncachedInputTokens: Int.max,
    cacheReadTokens: Int.max,
    cacheWriteTokens: Int.max)

  #expect(usage.totalInputTokens == Int.max)
}

@Test func priceCalculationRejectsPartiallyPricedUsage() {
  // Catches silently undercounting a model when one used category lacks a rate.
  let usage = NormalizedModelUsage(
    provider: .kimi,
    modelID: "kimi-k3",
    timestamp: .distantPast,
    uncachedInputTokens: 100,
    cacheWriteTokens: 1,
    outputTokens: 10)
  let price = ModelPrice(
    provider: .kimi,
    modelID: "kimi-k3",
    aliases: [],
    currency: "USD",
    uncachedInputPerMillion: 3,
    cacheReadPerMillion: Decimal(string: "0.3"),
    outputPerMillion: 15,
    sourceURL: sourceURL)

  #expect(CostCalculator.lineItem(usage: usage, price: price) == nil)
}

@Test func totalsKeepCurrenciesSeparate() {
  // Catches adding unrelated currencies into one misleading total.
  let usage = NormalizedModelUsage(
    provider: .codex, modelID: "gpt-5.5", timestamp: .distantPast)
  let items = [
    ModelCostLineItem(
      usage: usage,
      amount: CurrencyAmount(value: Decimal(string: "1.25")!, currency: "USD")),
    ModelCostLineItem(
      usage: usage,
      amount: CurrencyAmount(value: Decimal(string: "2.75")!, currency: "usd")),
    ModelCostLineItem(
      usage: usage,
      amount: CurrencyAmount(value: 9, currency: "CNY")),
  ]

  #expect(
    CostCalculator.totals(for: items)
      == [
        CurrencyAmount(value: 9, currency: "CNY"),
        CurrencyAmount(value: 4, currency: "USD"),
      ])
}
