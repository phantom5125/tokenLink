import Foundation
import Observation

@MainActor
@Observable
public final class UsageAnalyticsModel {
  public static let refreshTTL: TimeInterval = 300

  public private(set) var isRefreshing = false
  public private(set) var dataset: UsageAnalyticsDataset?
  public private(set) var snapshot: UsageAnalyticsSnapshot
  public private(set) var errorMessage: String?
  public var selectedSection: UsageAnalyticsSection = .overview
  public var selectedMetric: UsageAnalyticsMetric = .tokens
  public var selectedDimension: UsageAttributionDimension = .project
  public private(set) var selectedPreset: UsageAnalyticsRangePreset = .thirtyDays
  public private(set) var startDate: Date
  public private(set) var endDate: Date

  @ObservationIgnored private let loader: @Sendable () async throws -> UsageAnalyticsDataset
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var refreshGeneration = 0

  public init(
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() },
    loader: @escaping @Sendable () async throws -> UsageAnalyticsDataset
  ) {
    self.calendar = calendar
    self.now = now
    self.loader = loader
    let today = calendar.startOfDay(for: now())
    let initialStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
    endDate = today
    startDate = initialStart
    snapshot = UsageAnalyticsQuery.snapshot(
      dataset: nil,
      startDate: initialStart,
      endDate: today,
      calendar: calendar)
  }

  public static func empty() -> UsageAnalyticsModel {
    UsageAnalyticsModel {
      let now = Date()
      return UsageAnalyticsDataset(
        buckets: [],
        earliestEventAt: nil,
        latestEventAt: nil,
        metadata: UsageAnalyticsRefreshMetadata(
          scannedAt: now,
          discoveredFileCount: 0,
          reparsedFileCount: 0,
          reusedFileCount: 0,
          skippedFileCount: 0,
          oversizedRecordCount: 0,
          retainedEventCount: 0,
          storageBytes: 0,
          catalogVersion: "unavailable"))
    }
  }

  public func loadIfNeeded() async {
    if let scannedAt = dataset?.metadata.scannedAt,
      now().timeIntervalSince(scannedAt) < Self.refreshTTL
    {
      return
    }
    await refresh()
  }

  public func refresh() async {
    if let refreshTask {
      await refreshTask.value
      return
    }
    refreshGeneration += 1
    let generation = refreshGeneration
    let task = Task<Void, Never> { @MainActor [weak self] in
      guard let self else { return }
      self.isRefreshing = true
      defer {
        if self.refreshGeneration == generation {
          self.isRefreshing = false
          self.refreshTask = nil
        }
      }
      do {
        let loaded = try await self.loader()
        guard !Task.isCancelled else { return }
        self.dataset = loaded
        self.errorMessage = nil
        self.rebuildSnapshot()
      } catch is CancellationError {
        return
      } catch {
        self.errorMessage = "Local analytics history could not be refreshed."
      }
    }
    refreshTask = task
    await task.value
  }

  public func cancelRefresh() {
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    isRefreshing = false
  }

  public func selectPreset(_ preset: UsageAnalyticsRangePreset) {
    selectedPreset = preset
    guard preset != .custom else { return }
    let today = calendar.startOfDay(for: now())
    endDate = today
    startDate =
      calendar.date(byAdding: .day, value: -(preset.rawValue - 1), to: today)
      ?? today
    rebuildSnapshot()
  }

  public func setCustomRange(start: Date, end: Date) {
    selectedPreset = .custom
    let proposedStart = calendar.startOfDay(for: min(start, end))
    let proposedEnd = calendar.startOfDay(for: max(start, end))
    let boundedEnd = min(max(proposedEnd, minimumSelectableDate), maximumSelectableDate)
    let boundedStart = min(max(proposedStart, minimumSelectableDate), boundedEnd)
    startDate = boundedStart
    endDate = boundedEnd
    rebuildSnapshot()
  }

  public var minimumSelectableDate: Date {
    calendar.date(
      byAdding: .day,
      value: -(UsageAnalyticsService.historyDays - 1),
      to: maximumSelectableDate) ?? maximumSelectableDate
  }

  public var maximumSelectableDate: Date {
    calendar.startOfDay(for: now())
  }

  public var earliestAvailableDate: Date? {
    dataset?.earliestEventAt.map { calendar.startOfDay(for: $0) }
  }

  public var latestAvailableDate: Date? {
    dataset?.latestEventAt.map { calendar.startOfDay(for: $0) }
  }

  private func rebuildSnapshot() {
    snapshot = UsageAnalyticsQuery.snapshot(
      dataset: dataset,
      startDate: startDate,
      endDate: endDate,
      calendar: calendar)
  }
}
