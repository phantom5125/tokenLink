import Foundation

public enum MenuBarCostMetric: Codable, Equatable, Sendable {
  case none
  case localEstimate(ProviderID)
  case authoritativeBalance(accountID: UUID, currency: String)
}

public struct CurrencyAmount: Equatable, Sendable {
  public let value: Decimal
  public let currency: String

  public init(value: Decimal, currency: String) {
    self.value = value
    self.currency = currency.uppercased()
  }
}

public struct AccountBalance: Equatable, Sendable {
  public let available: CurrencyAmount
  public let purchased: CurrencyAmount?
  public let used: CurrencyAmount?

  public init(
    currency: String,
    available: Decimal,
    purchased: Decimal? = nil,
    used: Decimal? = nil
  ) {
    self.available = CurrencyAmount(value: available, currency: currency)
    self.purchased = purchased.map { CurrencyAmount(value: $0, currency: currency) }
    self.used = used.map { CurrencyAmount(value: $0, currency: currency) }
  }
}

public enum ProviderSpendPeriod: String, Codable, Equatable, Sendable {
  case daily
  case weekly
  case monthly
  case lifetime
}

public struct ProviderPeriodSpend: Equatable, Sendable {
  public let period: ProviderSpendPeriod
  public let amount: CurrencyAmount

  public init(period: ProviderSpendPeriod, amount: CurrencyAmount) {
    self.period = period
    self.amount = amount
  }
}

public enum CostWarning: Equatable, Sendable {
  case assumedFiveMinuteCacheWrite
  case partialSource(String)
  case unpricedModel(String)
}

public struct AuthoritativeCostSnapshot: Equatable, Sendable {
  public let provider: ProviderID
  public let balances: [AccountBalance]
  public let periodSpend: [ProviderPeriodSpend]
  public let isAvailable: Bool?
  public let warnings: [CostWarning]
  public let fetchedAt: Date

  public init(
    provider: ProviderID,
    balances: [AccountBalance],
    periodSpend: [ProviderPeriodSpend] = [],
    isAvailable: Bool? = nil,
    warnings: [CostWarning] = [],
    fetchedAt: Date
  ) {
    self.provider = provider
    self.balances = balances
    self.periodSpend = periodSpend
    self.isAvailable = isAvailable
    self.warnings = warnings
    self.fetchedAt = fetchedAt
  }
}

public enum CacheWriteDuration: String, Codable, Equatable, Sendable {
  case fiveMinutes
  case oneHour
}

public struct NormalizedModelUsage: Equatable, Sendable {
  public let provider: ProviderID
  public let modelID: String
  public let timestamp: Date
  public let uncachedInputTokens: Int
  public let cacheReadTokens: Int
  public let cacheWriteTokens: Int
  public let cacheWriteDuration: CacheWriteDuration?
  public let outputTokens: Int
  public let deduplicationKey: String

  public init(
    provider: ProviderID,
    modelID: String,
    timestamp: Date,
    uncachedInputTokens: Int = 0,
    cacheReadTokens: Int = 0,
    cacheWriteTokens: Int = 0,
    cacheWriteDuration: CacheWriteDuration? = nil,
    outputTokens: Int = 0,
    deduplicationKey: String = ""
  ) {
    self.provider = provider
    self.modelID = modelID
    self.timestamp = timestamp
    self.uncachedInputTokens = max(0, uncachedInputTokens)
    self.cacheReadTokens = max(0, cacheReadTokens)
    self.cacheWriteTokens = max(0, cacheWriteTokens)
    self.cacheWriteDuration = cacheWriteDuration
    self.outputTokens = max(0, outputTokens)
    self.deduplicationKey = deduplicationKey
  }

  public var totalInputTokens: Int {
    uncachedInputTokens + cacheReadTokens + cacheWriteTokens
  }
}

public struct LongContextPricing: Equatable, Sendable {
  public let thresholdInputTokens: Int
  public let inputMultiplier: Decimal
  public let outputMultiplier: Decimal

  public init(
    thresholdInputTokens: Int,
    inputMultiplier: Decimal,
    outputMultiplier: Decimal
  ) {
    self.thresholdInputTokens = max(0, thresholdInputTokens)
    self.inputMultiplier = inputMultiplier
    self.outputMultiplier = outputMultiplier
  }
}

public struct ModelPrice: Equatable, Sendable {
  public let provider: ProviderID
  public let modelID: String
  public let aliases: [String]
  public let currency: String
  public let uncachedInputPerMillion: Decimal?
  public let cacheReadPerMillion: Decimal?
  public let cacheWriteFiveMinutePerMillion: Decimal?
  public let cacheWriteOneHourPerMillion: Decimal?
  public let outputPerMillion: Decimal?
  public let sourceURL: URL
  public let longContext: LongContextPricing?

  public init(
    provider: ProviderID,
    modelID: String,
    aliases: [String],
    currency: String,
    uncachedInputPerMillion: Decimal?,
    cacheReadPerMillion: Decimal?,
    cacheWriteFiveMinutePerMillion: Decimal? = nil,
    cacheWriteOneHourPerMillion: Decimal? = nil,
    outputPerMillion: Decimal?,
    sourceURL: URL,
    longContext: LongContextPricing? = nil
  ) {
    self.provider = provider
    self.modelID = modelID
    self.aliases = aliases
    self.currency = currency.uppercased()
    self.uncachedInputPerMillion = uncachedInputPerMillion
    self.cacheReadPerMillion = cacheReadPerMillion
    self.cacheWriteFiveMinutePerMillion = cacheWriteFiveMinutePerMillion
    self.cacheWriteOneHourPerMillion = cacheWriteOneHourPerMillion
    self.outputPerMillion = outputPerMillion
    self.sourceURL = sourceURL
    self.longContext = longContext
  }
}

public struct ModelCostLineItem: Equatable, Sendable {
  public let usage: NormalizedModelUsage
  public let amount: CurrencyAmount
  public let warnings: [CostWarning]

  public init(
    usage: NormalizedModelUsage,
    amount: CurrencyAmount,
    warnings: [CostWarning] = []
  ) {
    self.usage = usage
    self.amount = amount
    self.warnings = warnings
  }
}

public struct EstimatedCostSnapshot: Equatable, Sendable {
  public let provider: ProviderID
  public let period: DateInterval
  public let lineItems: [ModelCostLineItem]
  public let totals: [CurrencyAmount]
  public let unknownModelIDs: [String]
  public let catalogVersion: String
  public let catalogEffectiveDate: Date
  public let scannedAt: Date

  public init(
    provider: ProviderID,
    period: DateInterval,
    lineItems: [ModelCostLineItem],
    totals: [CurrencyAmount],
    unknownModelIDs: [String],
    catalogVersion: String,
    catalogEffectiveDate: Date,
    scannedAt: Date
  ) {
    self.provider = provider
    self.period = period
    self.lineItems = lineItems
    self.totals = totals
    self.unknownModelIDs = unknownModelIDs
    self.catalogVersion = catalogVersion
    self.catalogEffectiveDate = catalogEffectiveDate
    self.scannedAt = scannedAt
  }
}

public enum CostCalculator {
  private static let tokensPerMillion = Decimal(1_000_000)

  public static func lineItem(
    usage: NormalizedModelUsage,
    price: ModelPrice
  ) -> ModelCostLineItem? {
    guard usage.provider == price.provider else { return nil }

    var warnings: [CostWarning] = []
    let cacheWriteRate: Decimal?
    switch usage.cacheWriteDuration {
    case .oneHour:
      cacheWriteRate = price.cacheWriteOneHourPerMillion
    case .fiveMinutes:
      cacheWriteRate = price.cacheWriteFiveMinutePerMillion
    case nil:
      cacheWriteRate = price.cacheWriteFiveMinutePerMillion
      if usage.cacheWriteTokens > 0 {
        warnings.append(.assumedFiveMinuteCacheWrite)
      }
    }

    guard let input = cost(tokens: usage.uncachedInputTokens, rate: price.uncachedInputPerMillion),
      let cacheRead = cost(tokens: usage.cacheReadTokens, rate: price.cacheReadPerMillion),
      let cacheWrite = cost(tokens: usage.cacheWriteTokens, rate: cacheWriteRate),
      let output = cost(tokens: usage.outputTokens, rate: price.outputPerMillion)
    else { return nil }

    let isLongContext =
      price.longContext.map {
        usage.totalInputTokens > $0.thresholdInputTokens
      } ?? false
    let inputMultiplier = isLongContext ? price.longContext?.inputMultiplier ?? 1 : 1
    let outputMultiplier = isLongContext ? price.longContext?.outputMultiplier ?? 1 : 1
    let total = (input + cacheRead + cacheWrite) * inputMultiplier + output * outputMultiplier

    return ModelCostLineItem(
      usage: usage,
      amount: CurrencyAmount(value: total, currency: price.currency),
      warnings: warnings)
  }

  public static func totals(for lineItems: [ModelCostLineItem]) -> [CurrencyAmount] {
    var values: [String: Decimal] = [:]
    for item in lineItems {
      values[item.amount.currency, default: 0] += item.amount.value
    }
    return values.keys.sorted().map {
      CurrencyAmount(value: values[$0] ?? 0, currency: $0)
    }
  }

  private static func cost(tokens: Int, rate: Decimal?) -> Decimal? {
    if tokens == 0 { return 0 }
    guard let rate else { return nil }
    return Decimal(tokens) * rate / tokensPerMillion
  }
}
