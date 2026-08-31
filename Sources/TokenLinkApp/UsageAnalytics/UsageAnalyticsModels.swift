import Foundation
import TokenLinkCore

public enum UsageAnalyticsMetric: String, CaseIterable, Identifiable, Sendable {
  case tokens
  case cost
  case activeTime

  public var id: Self { self }
}

public enum UsageAttributionDimension: String, CaseIterable, Identifiable, Sendable {
  case project
  case model
  case effort
  case session

  public var id: Self { self }
}

public enum UsageAnalyticsSection: String, CaseIterable, Identifiable, Sendable {
  case overview
  case trends
  case attribution
  case costs

  public var id: Self { self }
}

public enum UsageAnalyticsRangePreset: Int, CaseIterable, Identifiable, Sendable {
  case sevenDays = 7
  case thirtyDays = 30
  case ninetyDays = 90
  case year = 365
  case custom = 0

  public var id: Self { self }
}

struct UsageAnalyticsStoredEvent: Codable, Equatable, Sendable {
  let timestamp: Date
  let provider: ProviderID
  let projectID: String
  let projectName: String
  let modelID: String
  let effort: String
  let sessionID: String
  let processingTier: CostProcessingTier
  let uncachedInputTokens: Int
  let cacheReadTokens: Int
  let cacheWriteTokens: Int
  let outputTokens: Int
  let requestCount: Int
  let costNanoUSD: Int64
  let isPriced: Bool
  let deduplicationKey: String

  var totalInputTokens: Int {
    Self.saturatingAdd(
      Self.saturatingAdd(uncachedInputTokens, cacheReadTokens),
      cacheWriteTokens)
  }

  var totalTokens: Int {
    Self.saturatingAdd(totalInputTokens, outputTokens)
  }

  private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
    return result.overflow ? Int.max : result.partialValue
  }
}

struct UsageAnalyticsFileCache: Codable, Equatable, Sendable {
  let provider: ProviderID
  let byteCount: Int
  let modifiedAt: Date
  let events: [UsageAnalyticsStoredEvent]
  let oversizedRecordCount: Int
}

struct UsageAnalyticsDatabase: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  var updatedAt: Date
  var files: [String: UsageAnalyticsFileCache]

  static func empty(at date: Date) -> Self {
    Self(schemaVersion: currentSchemaVersion, updatedAt: date, files: [:])
  }
}

public struct UsageAnalyticsRefreshMetadata: Equatable, Sendable {
  public let scannedAt: Date
  public let discoveredFileCount: Int
  public let reparsedFileCount: Int
  public let reusedFileCount: Int
  public let skippedFileCount: Int
  public let oversizedRecordCount: Int
  public let retainedEventCount: Int
  public let storageBytes: Int
  public let catalogVersion: String

  public init(
    scannedAt: Date,
    discoveredFileCount: Int,
    reparsedFileCount: Int,
    reusedFileCount: Int,
    skippedFileCount: Int,
    oversizedRecordCount: Int,
    retainedEventCount: Int,
    storageBytes: Int,
    catalogVersion: String
  ) {
    self.scannedAt = scannedAt
    self.discoveredFileCount = max(0, discoveredFileCount)
    self.reparsedFileCount = max(0, reparsedFileCount)
    self.reusedFileCount = max(0, reusedFileCount)
    self.skippedFileCount = max(0, skippedFileCount)
    self.oversizedRecordCount = max(0, oversizedRecordCount)
    self.retainedEventCount = max(0, retainedEventCount)
    self.storageBytes = max(0, storageBytes)
    self.catalogVersion = catalogVersion
  }
}

public struct UsageAnalyticsBucket: Equatable, Sendable {
  public let hour: Date
  public let provider: ProviderID
  public let projectID: String
  public let projectName: String
  public let modelID: String
  public let effort: String
  public let sessionID: String
  public let processingTier: CostProcessingTier
  public var uncachedInputTokens: Int
  public var cacheReadTokens: Int
  public var cacheWriteTokens: Int
  public var outputTokens: Int
  public var requestCount: Int
  public var costNanoUSD: Int64
  public var pricedTokens: Int
  public var activeSeconds: Int

  public var totalInputTokens: Int {
    Self.saturatingAdd(
      Self.saturatingAdd(uncachedInputTokens, cacheReadTokens),
      cacheWriteTokens)
  }

  public var totalTokens: Int {
    Self.saturatingAdd(totalInputTokens, outputTokens)
  }

  public var costUSD: Double {
    Double(costNanoUSD) / 1_000_000_000
  }

  mutating func add(_ event: UsageAnalyticsStoredEvent) {
    uncachedInputTokens = Self.saturatingAdd(
      uncachedInputTokens, event.uncachedInputTokens)
    cacheReadTokens = Self.saturatingAdd(cacheReadTokens, event.cacheReadTokens)
    cacheWriteTokens = Self.saturatingAdd(cacheWriteTokens, event.cacheWriteTokens)
    outputTokens = Self.saturatingAdd(outputTokens, event.outputTokens)
    requestCount = Self.saturatingAdd(requestCount, event.requestCount)
    costNanoUSD = Self.saturatingAdd(costNanoUSD, event.costNanoUSD)
    if event.isPriced {
      pricedTokens = Self.saturatingAdd(pricedTokens, event.totalTokens)
    }
  }

  mutating func addActiveSeconds(_ value: Int) {
    activeSeconds = Self.saturatingAdd(activeSeconds, max(0, value))
  }

  private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
    return result.overflow ? Int.max : result.partialValue
  }

  private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
    return result.overflow ? Int64.max : result.partialValue
  }
}

public struct UsageAnalyticsDataset: Equatable, Sendable {
  public let buckets: [UsageAnalyticsBucket]
  public let earliestEventAt: Date?
  public let latestEventAt: Date?
  public let metadata: UsageAnalyticsRefreshMetadata

  public init(
    buckets: [UsageAnalyticsBucket],
    earliestEventAt: Date?,
    latestEventAt: Date?,
    metadata: UsageAnalyticsRefreshMetadata
  ) {
    self.buckets = buckets
    self.earliestEventAt = earliestEventAt
    self.latestEventAt = latestEventAt
    self.metadata = metadata
  }
}

public struct UsageAnalyticsTotals: Equatable, Sendable {
  public var uncachedInputTokens = 0
  public var cacheReadTokens = 0
  public var cacheWriteTokens = 0
  public var outputTokens = 0
  public var requestCount = 0
  public var costNanoUSD: Int64 = 0
  public var pricedTokens = 0
  public var activeSeconds = 0
  public var projectCount = 0
  public var modelCount = 0
  public var sessionCount = 0

  public var totalInputTokens: Int {
    saturatingAdd(saturatingAdd(uncachedInputTokens, cacheReadTokens), cacheWriteTokens)
  }

  public var totalTokens: Int {
    saturatingAdd(totalInputTokens, outputTokens)
  }

  public var cacheReuseRatio: Double? {
    guard totalInputTokens > 0 else { return nil }
    return Double(cacheReadTokens) / Double(totalInputTokens)
  }

  public var pricingCoverage: Double? {
    guard totalTokens > 0 else { return nil }
    return min(1, Double(pricedTokens) / Double(totalTokens))
  }

  public var costUSD: Double {
    Double(costNanoUSD) / 1_000_000_000
  }
}

public struct UsageAnalyticsTimePoint: Identifiable, Equatable, Sendable {
  public let date: Date
  public let totals: UsageAnalyticsTotals
  public var id: Date { date }
}

public struct UsageAnalyticsHourPoint: Identifiable, Equatable, Sendable {
  public let hour: Int
  public let current: UsageAnalyticsTotals
  public let previous: UsageAnalyticsTotals
  public var id: Int { hour }
}

public struct UsageAnalyticsDay: Identifiable, Equatable, Sendable {
  public let date: Date
  public let totals: UsageAnalyticsTotals
  public var id: Date { date }
}

public struct UsageAttributionRow: Identifiable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let totals: UsageAnalyticsTotals
  public let shareOfTokens: Double
  public let shareOfCost: Double
  public let shareOfActiveTime: Double
}

public struct UsageAnalyticsSnapshot: Equatable, Sendable {
  public let interval: DateInterval
  public let comparisonInterval: DateInterval
  public let current: UsageAnalyticsTotals
  public let previous: UsageAnalyticsTotals
  public let timeline: [UsageAnalyticsTimePoint]
  public let comparisonTimeline: [UsageAnalyticsTimePoint]
  public let calendarDays: [UsageAnalyticsDay]
  public let hourlyDistribution: [UsageAnalyticsHourPoint]
  public let attribution: [UsageAttributionDimension: [UsageAttributionRow]]
  public let metadata: UsageAnalyticsRefreshMetadata?

  public static func empty(
    interval: DateInterval,
    comparisonInterval: DateInterval
  ) -> Self {
    Self(
      interval: interval,
      comparisonInterval: comparisonInterval,
      current: UsageAnalyticsTotals(),
      previous: UsageAnalyticsTotals(),
      timeline: [],
      comparisonTimeline: [],
      calendarDays: [],
      hourlyDistribution: [],
      attribution: [:],
      metadata: nil)
  }
}

enum UsageAnalyticsQuery {
  static func snapshot(
    dataset: UsageAnalyticsDataset?,
    startDate: Date,
    endDate: Date,
    calendar: Calendar = .current
  ) -> UsageAnalyticsSnapshot {
    let start = calendar.startOfDay(for: min(startDate, endDate))
    let finalDay = calendar.startOfDay(for: max(startDate, endDate))
    let endExclusive = calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay
    let interval = DateInterval(start: start, end: endExclusive)
    let dayCount = max(
      1,
      calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
    let comparisonStart =
      calendar.date(byAdding: .day, value: -dayCount, to: interval.start)
      ?? interval.start.addingTimeInterval(-Double(dayCount) * 86_400)
    let comparison = DateInterval(
      start: comparisonStart,
      end: interval.start)
    guard let dataset else {
      return .empty(interval: interval, comparisonInterval: comparison)
    }

    let currentBuckets = dataset.buckets.filter {
      $0.hour >= interval.start && $0.hour < interval.end
    }
    let previousBuckets = dataset.buckets.filter {
      $0.hour >= comparison.start && $0.hour < comparison.end
    }
    let currentTotals = totals(currentBuckets)
    let previousTotals = totals(previousBuckets)
    let timelineComponent: Calendar.Component = dayCount <= 7 ? .hour : .day
    let timeline = timelinePoints(
      currentBuckets,
      interval: interval,
      component: timelineComponent,
      calendar: calendar)
    let previousTimeline = timelinePoints(
      previousBuckets,
      interval: comparison,
      component: timelineComponent,
      calendar: calendar)
    let shiftedComparison = previousTimeline.map {
      UsageAnalyticsTimePoint(
        date: calendar.date(byAdding: .day, value: dayCount, to: $0.date)
          ?? $0.date.addingTimeInterval(Double(dayCount) * 86_400),
        totals: $0.totals)
    }

    return UsageAnalyticsSnapshot(
      interval: interval,
      comparisonInterval: comparison,
      current: currentTotals,
      previous: previousTotals,
      timeline: timeline,
      comparisonTimeline: shiftedComparison,
      calendarDays: calendarPoints(
        currentBuckets,
        interval: interval,
        calendar: calendar),
      hourlyDistribution: hourPoints(
        current: currentBuckets,
        previous: previousBuckets,
        calendar: calendar),
      attribution: Dictionary(
        uniqueKeysWithValues: UsageAttributionDimension.allCases.map { dimension in
          (
            dimension,
            attributionRows(
              currentBuckets,
              dimension: dimension,
              totals: currentTotals)
          )
        }),
      metadata: dataset.metadata)
  }

  private static func timelinePoints(
    _ buckets: [UsageAnalyticsBucket],
    interval: DateInterval,
    component: Calendar.Component,
    calendar: Calendar
  ) -> [UsageAnalyticsTimePoint] {
    var values: [Date: [UsageAnalyticsBucket]] = [:]
    for bucket in buckets {
      let date =
        component == .hour
        ? calendar.dateInterval(of: .hour, for: bucket.hour)?.start ?? bucket.hour
        : calendar.startOfDay(for: bucket.hour)
      values[date, default: []].append(bucket)
    }
    var points: [UsageAnalyticsTimePoint] = []
    var cursor =
      component == .hour
      ? calendar.dateInterval(of: .hour, for: interval.start)?.start ?? interval.start
      : calendar.startOfDay(for: interval.start)
    while cursor < interval.end {
      points.append(
        UsageAnalyticsTimePoint(
          date: cursor,
          totals: totals(values[cursor] ?? [])))
      guard let next = calendar.date(byAdding: component, value: 1, to: cursor),
        next > cursor
      else { break }
      cursor = next
    }
    return points
  }

  private static func calendarPoints(
    _ buckets: [UsageAnalyticsBucket],
    interval: DateInterval,
    calendar: Calendar
  ) -> [UsageAnalyticsDay] {
    var values: [Date: [UsageAnalyticsBucket]] = [:]
    for bucket in buckets {
      values[calendar.startOfDay(for: bucket.hour), default: []].append(bucket)
    }
    var days: [UsageAnalyticsDay] = []
    var cursor = calendar.startOfDay(for: interval.start)
    while cursor < interval.end {
      days.append(UsageAnalyticsDay(date: cursor, totals: totals(values[cursor] ?? [])))
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else {
        break
      }
      cursor = next
    }
    return days
  }

  private static func hourPoints(
    current: [UsageAnalyticsBucket],
    previous: [UsageAnalyticsBucket],
    calendar: Calendar
  ) -> [UsageAnalyticsHourPoint] {
    var currentByHour: [Int: [UsageAnalyticsBucket]] = [:]
    var previousByHour: [Int: [UsageAnalyticsBucket]] = [:]
    for bucket in current {
      currentByHour[calendar.component(.hour, from: bucket.hour), default: []].append(bucket)
    }
    for bucket in previous {
      previousByHour[calendar.component(.hour, from: bucket.hour), default: []].append(bucket)
    }
    return (0..<24).map {
      UsageAnalyticsHourPoint(
        hour: $0,
        current: totals(currentByHour[$0] ?? []),
        previous: totals(previousByHour[$0] ?? []))
    }
  }

  private static func attributionRows(
    _ buckets: [UsageAnalyticsBucket],
    dimension: UsageAttributionDimension,
    totals overall: UsageAnalyticsTotals
  ) -> [UsageAttributionRow] {
    struct Group {
      var label: String
      var buckets: [UsageAnalyticsBucket]
    }
    var groups: [String: Group] = [:]
    for bucket in buckets {
      let id: String
      let label: String
      switch dimension {
      case .project:
        id = bucket.projectID
        label = bucket.projectName
      case .model:
        id = "\(bucket.provider.rawValue):\(bucket.modelID)"
        label = "\(bucket.provider.rawValue.capitalized) · \(bucket.modelID)"
      case .effort:
        id = bucket.effort
        label = bucket.effort.capitalized
      case .session:
        id = bucket.sessionID
        label = "Session \(bucket.sessionID.prefix(8))"
      }
      var group = groups[id] ?? Group(label: label, buckets: [])
      group.buckets.append(bucket)
      groups[id] = group
    }
    return groups.map { id, group in
      let groupTotals = totals(group.buckets)
      return UsageAttributionRow(
        id: id,
        label: group.label,
        totals: groupTotals,
        shareOfTokens: share(groupTotals.totalTokens, of: overall.totalTokens),
        shareOfCost: share(groupTotals.costNanoUSD, of: overall.costNanoUSD),
        shareOfActiveTime: share(groupTotals.activeSeconds, of: overall.activeSeconds))
    }
    .sorted {
      if $0.totals.totalTokens != $1.totals.totalTokens {
        return $0.totals.totalTokens > $1.totals.totalTokens
      }
      return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
    }
  }

  private static func totals(_ buckets: [UsageAnalyticsBucket]) -> UsageAnalyticsTotals {
    var result = UsageAnalyticsTotals()
    var projects: Set<String> = []
    var models: Set<String> = []
    var sessions: Set<String> = []
    for bucket in buckets {
      result.uncachedInputTokens = saturatingAdd(
        result.uncachedInputTokens, bucket.uncachedInputTokens)
      result.cacheReadTokens = saturatingAdd(result.cacheReadTokens, bucket.cacheReadTokens)
      result.cacheWriteTokens = saturatingAdd(result.cacheWriteTokens, bucket.cacheWriteTokens)
      result.outputTokens = saturatingAdd(result.outputTokens, bucket.outputTokens)
      result.requestCount = saturatingAdd(result.requestCount, bucket.requestCount)
      result.costNanoUSD = saturatingAdd(result.costNanoUSD, bucket.costNanoUSD)
      result.pricedTokens = saturatingAdd(result.pricedTokens, bucket.pricedTokens)
      result.activeSeconds = saturatingAdd(result.activeSeconds, bucket.activeSeconds)
      projects.insert(bucket.projectID)
      models.insert("\(bucket.provider.rawValue):\(bucket.modelID)")
      sessions.insert(bucket.sessionID)
    }
    result.projectCount = projects.count
    result.modelCount = models.count
    result.sessionCount = sessions.count
    return result
  }
}

private func share<T: BinaryInteger>(_ value: T, of total: T) -> Double {
  guard total > 0 else { return 0 }
  return min(1, Double(value) / Double(total))
}

private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
  return result.overflow ? Int.max : result.partialValue
}

private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
  let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
  return result.overflow ? Int64.max : result.partialValue
}
