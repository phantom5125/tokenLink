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
      let fallbackProcessingTier = observer.codexFallbackProcessingTier()
      return try estimate(
        CodexCostRecordParser.self,
        since: since,
        through: through,
        makeParser: {
          CodexCostRecordParser(
            fallbackProcessingTier: fallbackProcessingTier)
        })
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

  /// Builds Today / Week / Month from one bounded transcript pass. Changing
  /// the visible period therefore never reopens local session files.
  public func estimatePeriods(
    provider: ProviderID,
    through: Date,
    calendar: Calendar = .current
  ) throws -> EstimatedCostPeriodCollection {
    switch provider {
    case .codex:
      let fallbackProcessingTier = observer.codexFallbackProcessingTier()
      return try estimatePeriods(
        CodexCostRecordParser.self,
        through: through,
        calendar: calendar,
        makeParser: {
          CodexCostRecordParser(
            fallbackProcessingTier: fallbackProcessingTier)
        })
    case .claude:
      return try estimatePeriods(
        ClaudeCostRecordParser.self,
        through: through,
        calendar: calendar)
    case .kimi:
      return try estimatePeriods(
        KimiCostRecordParser.self,
        through: through,
        calendar: calendar)
    default:
      throw LocalCostEstimatorError.unsupportedProvider(provider)
    }
  }

  private func estimate<P: LocalUsageRecordParser>(
    _ parser: P.Type,
    since: Date,
    through: Date,
    makeParser: () -> P = { P() }
  ) throws -> EstimatedCostSnapshot {
    var aggregates: [AggregateKey: CostAggregate] = [:]
    var unknownModelIDs: Set<String> = []
    var seenEventIDs: Set<String> = []
    var rejectedOverflow = false

    let report = try observer.scanRecords(
      parser,
      since: since,
      through: through,
      makeParser: makeParser
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
        outputTokens: usage.outputTokens,
        processingTier: usage.processingTier)
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

  private func estimatePeriods<P: LocalUsageRecordParser>(
    _ parser: P.Type,
    through: Date,
    calendar: Calendar,
    makeParser: () -> P = { P() }
  ) throws -> EstimatedCostPeriodCollection {
    let intervals = Dictionary(
      uniqueKeysWithValues: CostDisplayPeriod.allCases.map {
        ($0, $0.interval(endingAt: through, calendar: calendar))
      })
    guard let scanStart = intervals[.month]?.start else {
      throw LocalCostEstimatorError.invalidInterval
    }

    var aggregates = Dictionary(
      uniqueKeysWithValues: CostDisplayPeriod.allCases.map {
        ($0, [AggregateKey: CostAggregate]())
      })
    var unknownModelIDs = Dictionary(
      uniqueKeysWithValues: CostDisplayPeriod.allCases.map {
        ($0, Set<String>())
      })
    var rejectedOverflow: Set<CostDisplayPeriod> = []
    var seenEventIDs: Set<String> = []

    let report = try observer.scanRecords(
      parser,
      since: scanStart,
      through: through,
      makeParser: makeParser
    ) { usage in
      if !usage.deduplicationKey.isEmpty,
        !seenEventIDs.insert(usage.deduplicationKey).inserted
      {
        return
      }
      let matchingPeriods = CostDisplayPeriod.allCases.filter { period in
        guard let interval = intervals[period] else { return false }
        return usage.timestamp >= interval.start && usage.timestamp <= interval.end
      }
      guard !matchingPeriods.isEmpty else { return }
      guard let price = catalog.entry(provider: P.provider, modelID: usage.modelID) else {
        for period in matchingPeriods {
          unknownModelIDs[period, default: []].insert(usage.modelID)
        }
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
        outputTokens: usage.outputTokens,
        processingTier: usage.processingTier)
      guard let item = CostCalculator.lineItem(usage: canonicalUsage, price: price) else {
        for period in matchingPeriods {
          unknownModelIDs[period, default: []].insert(usage.modelID)
        }
        return
      }
      let key = AggregateKey(modelID: price.modelID, currency: item.amount.currency)
      for period in matchingPeriods {
        var periodAggregates = aggregates[period] ?? [:]
        var aggregate =
          periodAggregates[key]
          ?? CostAggregate(provider: P.provider, modelID: price.modelID)
        if aggregate.add(item) {
          periodAggregates[key] = aggregate
          aggregates[period] = periodAggregates
        } else {
          rejectedOverflow.insert(period)
        }
      }
    }

    let skippedFiles = report.oversizedFileCount + report.unreadableFileCount
    let snapshots: [CostDisplayPeriod: EstimatedCostSnapshot] = Dictionary(
      uniqueKeysWithValues: CostDisplayPeriod.allCases.map { period in
        let interval = intervals[period] ?? period.interval(endingAt: through, calendar: calendar)
        let periodAggregates = aggregates[period] ?? [:]
        let lineItems = periodAggregates.keys.sorted().compactMap { key in
          periodAggregates[key]?.lineItem(currency: key.currency)
        }
        var warnings: [CostWarning] = []
        if skippedFiles > 0 || report.oversizedRecordCount > 0 {
          warnings.append(
            .partialLocalScan(
              fileCount: skippedFiles,
              recordCount: report.oversizedRecordCount))
        }
        if rejectedOverflow.contains(period) {
          warnings.append(.invalidTokenCount)
        }
        let snapshot = EstimatedCostSnapshot(
          provider: P.provider,
          period: interval,
          lineItems: lineItems,
          totals: CostCalculator.totals(for: lineItems),
          unknownModelIDs: (unknownModelIDs[period] ?? []).sorted(),
          warnings: warnings,
          catalogVersion: catalog.version,
          catalogEffectiveDate: catalog.effectiveDate,
          scannedAt: now())
        return (period, snapshot)
      })
    return EstimatedCostPeriodCollection(provider: P.provider, snapshots: snapshots)
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
  var componentTokens: [CostComponentCategory: Int] = [:]
  var componentAmounts: [CostComponentCategory: Decimal] = [:]
  var price: ModelPrice?
  var requestCount = 0
  var longContextRequestCount = 0
  var fastRequestCount = 0
  var warnings: [CostWarning] = []

  mutating func add(_ item: ModelCostLineItem) -> Bool {
    let nextUncached = uncachedInputTokens.addingReportingOverflow(
      item.usage.uncachedInputTokens)
    let nextCacheRead = cacheReadTokens.addingReportingOverflow(item.usage.cacheReadTokens)
    let nextCacheWrite = cacheWriteTokens.addingReportingOverflow(
      item.usage.cacheWriteTokens)
    let nextOutput = outputTokens.addingReportingOverflow(item.usage.outputTokens)
    let nextRequestCount = requestCount.addingReportingOverflow(item.requestCount)
    let nextLongContextRequestCount = longContextRequestCount.addingReportingOverflow(
      item.longContextRequestCount)
    let nextFastRequestCount = fastRequestCount.addingReportingOverflow(item.fastRequestCount)
    var nextComponentTokens = componentTokens
    for component in item.components {
      let next = nextComponentTokens[component.category, default: 0]
        .addingReportingOverflow(component.tokens)
      guard !next.overflow else { return false }
      nextComponentTokens[component.category] = next.partialValue
    }
    guard
      !nextUncached.overflow,
      !nextCacheRead.overflow,
      !nextCacheWrite.overflow,
      !nextOutput.overflow,
      !nextRequestCount.overflow,
      !nextLongContextRequestCount.overflow,
      !nextFastRequestCount.overflow
    else { return false }

    latestTimestamp = max(latestTimestamp, item.usage.timestamp)
    uncachedInputTokens = nextUncached.partialValue
    cacheReadTokens = nextCacheRead.partialValue
    cacheWriteTokens = nextCacheWrite.partialValue
    outputTokens = nextOutput.partialValue
    componentTokens = nextComponentTokens
    amount += item.amount.value
    for component in item.components {
      componentAmounts[component.category, default: 0] += component.amount.value
    }
    price = price ?? item.price
    requestCount = nextRequestCount.partialValue
    longContextRequestCount = nextLongContextRequestCount.partialValue
    fastRequestCount = nextFastRequestCount.partialValue
    for warning in item.warnings where !warnings.contains(warning) {
      warnings.append(warning)
    }
    return true
  }

  func lineItem(currency: String) -> ModelCostLineItem {
    let components: [ModelCostComponent] = CostComponentCategory.allCases.compactMap { category in
      guard let tokens = componentTokens[category], tokens > 0 else { return nil }
      return ModelCostComponent(
        category: category,
        tokens: tokens,
        amount: CurrencyAmount(
          value: componentAmounts[category, default: 0],
          currency: currency))
    }
    return ModelCostLineItem(
      usage: NormalizedModelUsage(
        provider: provider,
        modelID: modelID,
        timestamp: latestTimestamp,
        uncachedInputTokens: uncachedInputTokens,
        cacheReadTokens: cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens,
        outputTokens: outputTokens),
      amount: CurrencyAmount(value: amount, currency: currency),
      components: components,
      price: price,
      requestCount: requestCount,
      longContextRequestCount: longContextRequestCount,
      fastRequestCount: fastRequestCount,
      warnings: warnings)
  }
}
