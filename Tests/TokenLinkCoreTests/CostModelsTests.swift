import Foundation
import Testing

@testable import TokenLinkCore

private let sourceURL = URL(string: "https://example.com/pricing")!

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
  #expect(
    try #require(CostCalculator.lineItem(usage: overBoundary, price: price)).amount.value
      == Decimal(string: "47.72001"))
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
