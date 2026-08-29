import Foundation
import TokenLinkCore
import TokenLinkProviders

public enum LocalCostEstimatorError: Error, Equatable, Sendable {
  case invalidInterval
  case unsupportedProvider(ProviderID)
}

public struct LocalCostEstimator: Sendable {
  private let observer: LocalUsageObserver
  private let catalog: PriceCatalog
  private let now: @Sendable () -> Date

  public init(
    observer: LocalUsageObserver,
    catalog: PriceCatalog,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.observer = observer
    self.catalog = catalog
    self.now = now
  }

  public func estimate(
    provider: ProviderID,
    since: Date,
    through: Date
  ) throws -> EstimatedCostSnapshot {
    guard since <= through else { throw LocalCostEstimatorError.invalidInterval }
    switch provider {
    case .codex:
      return try estimate(
        CodexCostRecordParser.self,
        since: since,
        through: through)
    case .claude:
      return try estimate(
        ClaudeCostRecordParser.self,
        since: since,
        through: through)
    case .kimi:
      return try estimate(
        KimiCostRecordParser.self,
        since: since,
        through: through)
    default:
      throw LocalCostEstimatorError.unsupportedProvider(provider)
    }
  }

  private func estimate<P: LocalUsageRecordParser>(
    _ parser: P.Type,
    since: Date,
    through: Date
  ) throws -> EstimatedCostSnapshot {
    var aggregates: [AggregateKey: CostAggregate] = [:]
    var unknownModelIDs: Set<String> = []
    var seenEventIDs: Set<String> = []
    var rejectedOverflow = false

    let report = try observer.scanRecords(
      parser,
      since: since,
      through: through
    ) { usage in
      if !usage.deduplicationKey.isEmpty,
        !seenEventIDs.insert(usage.deduplicationKey).inserted
      {
        return
      }
      guard let price = catalog.entry(provider: P.provider, modelID: usage.modelID) else {
        unknownModelIDs.insert(usage.modelID)
        return
      }
      let canonicalUsage = NormalizedModelUsage(
        provider: usage.provider,
        modelID: price.modelID,
        timestamp: usage.timestamp,
        uncachedInputTokens: usage.uncachedInputTokens,
        cacheReadTokens: usage.cacheReadTokens,
        cacheWriteTokens: usage.cacheWriteTokens,
        cacheWriteDuration: usage.cacheWriteDuration,
        outputTokens: usage.outputTokens)
      guard let item = CostCalculator.lineItem(usage: canonicalUsage, price: price) else {
        unknownModelIDs.insert(usage.modelID)
        return
      }
      let key = AggregateKey(
        modelID: price.modelID,
        currency: item.amount.currency)
      var aggregate =
        aggregates[key] ?? CostAggregate(provider: P.provider, modelID: price.modelID)
      if aggregate.add(item) {
        aggregates[key] = aggregate
      } else {
        rejectedOverflow = true
      }
    }

    let lineItems = aggregates.keys.sorted().compactMap { key in
      aggregates[key]?.lineItem(currency: key.currency)
    }
    var warnings: [CostWarning] = []
    let skippedFiles = report.oversizedFileCount + report.unreadableFileCount
    if skippedFiles > 0 || report.oversizedRecordCount > 0 {
      warnings.append(
        .partialLocalScan(
          fileCount: skippedFiles,
          recordCount: report.oversizedRecordCount))
    }
    if rejectedOverflow {
      warnings.append(.invalidTokenCount)
    }
    return EstimatedCostSnapshot(
      provider: P.provider,
      period: DateInterval(start: since, end: through),
      lineItems: lineItems,
      totals: CostCalculator.totals(for: lineItems),
      unknownModelIDs: unknownModelIDs.sorted(),
      warnings: warnings,
      catalogVersion: catalog.version,
      catalogEffectiveDate: catalog.effectiveDate,
      scannedAt: now())
  }
}

private struct AggregateKey: Hashable, Comparable {
  let modelID: String
  let currency: String

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.modelID != rhs.modelID { return lhs.modelID < rhs.modelID }
    return lhs.currency < rhs.currency
  }
}

private struct CostAggregate {
  let provider: ProviderID
  let modelID: String
  var latestTimestamp = Date.distantPast
  var uncachedInputTokens = 0
  var cacheReadTokens = 0
  var cacheWriteTokens = 0
  var outputTokens = 0
  var amount: Decimal = 0
  var warnings: [CostWarning] = []

  mutating func add(_ item: ModelCostLineItem) -> Bool {
    let nextUncached = uncachedInputTokens.addingReportingOverflow(
      item.usage.uncachedInputTokens)
    let nextCacheRead = cacheReadTokens.addingReportingOverflow(item.usage.cacheReadTokens)
    let nextCacheWrite = cacheWriteTokens.addingReportingOverflow(
      item.usage.cacheWriteTokens)
    let nextOutput = outputTokens.addingReportingOverflow(item.usage.outputTokens)
    guard
      !nextUncached.overflow,
      !nextCacheRead.overflow,
      !nextCacheWrite.overflow,
      !nextOutput.overflow
    else { return false }

    latestTimestamp = max(latestTimestamp, item.usage.timestamp)
    uncachedInputTokens = nextUncached.partialValue
    cacheReadTokens = nextCacheRead.partialValue
    cacheWriteTokens = nextCacheWrite.partialValue
    outputTokens = nextOutput.partialValue
    amount += item.amount.value
    for warning in item.warnings where !warnings.contains(warning) {
      warnings.append(warning)
    }
    return true
  }

  func lineItem(currency: String) -> ModelCostLineItem {
    ModelCostLineItem(
      usage: NormalizedModelUsage(
        provider: provider,
        modelID: modelID,
        timestamp: latestTimestamp,
        uncachedInputTokens: uncachedInputTokens,
        cacheReadTokens: cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens,
        outputTokens: outputTokens),
      amount: CurrencyAmount(value: amount, currency: currency),
      warnings: warnings)
  }
}
