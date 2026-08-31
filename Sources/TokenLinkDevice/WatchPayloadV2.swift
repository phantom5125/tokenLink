import Foundation
import TokenLinkCore

public struct WatchWindowPayload: Codable, Equatable, Sendable {
  public let id: String  // "5h" | "weekly" | "monthly" | "primary" | ...
  public let remainingPercent: Double
  public let resetInSeconds: Int
  /// Optional known cycle length. New firmware uses it to animate the
  /// time-proportional fair-pace marker; older firmware ignores the field.
  public let windowDurationSeconds: Int?

  public init(
    id: String,
    remainingPercent: Double,
    resetInSeconds: Int,
    windowDurationSeconds: Int? = nil
  ) {
    self.id = id
    self.remainingPercent = remainingPercent
    self.resetInSeconds = resetInSeconds
    self.windowDurationSeconds = windowDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
  }

  enum CodingKeys: String, CodingKey {
    case id
    case remainingPercent = "remaining_percent"
    case resetInSeconds = "reset_in_seconds"
    case windowDurationSeconds = "window_duration_seconds"
  }
}

/// Optional watch face settings carried inside the v2 payload. Values are
/// plain strings so newer firmware options decode without a Mac-side update.
public struct WatchSettingsPayload: Codable, Equatable, Sendable {
  public let theme: String  // "data" | "pet"
  public let wake: String  // "raise" | "tap"
  public let hourFormat: String  // "system" | "h12" | "h24"

  public init(theme: String, wake: String, hourFormat: String) {
    self.theme = theme
    self.wake = wake
    self.hourFormat = hourFormat
  }

  enum CodingKeys: String, CodingKey {
    case theme
    case wake
    case hourFormat = "hour_format"
  }
}

public struct WatchPayloadV2: Codable, Equatable, Sendable {
  public static let protocolVersion = 2

  public let v: Int  // always 2
  public let providerID: String
  public let windows: [WatchWindowPayload]  // ≤ 3
  public let workItems: [WorkItemPayload]  // ≤ 3
  /// The firmware distinguishes an omitted `work_items` key (leave the
  /// current session list unchanged) from an explicitly empty array (clear
  /// it). Multi-provider batches use this to carry the full list only once.
  public let includesWorkItems: Bool
  /// Full Mac-side active count; may exceed the three displayed work items.
  public let activeSessionCount: Int?
  public let settings: WatchSettingsPayload?
  public let syncedAt: Int

  public init(
    providerID: String,
    windows: [WatchWindowPayload],
    workItems: [WorkItemPayload],
    activeSessionCount: Int? = nil,
    settings: WatchSettingsPayload? = nil,
    syncedAt: Int,
    includesWorkItems: Bool = true
  ) {
    self.v = Self.protocolVersion
    self.providerID = providerID
    self.windows = windows
    self.workItems = workItems
    self.includesWorkItems = includesWorkItems
    self.activeSessionCount = activeSessionCount
    self.settings = settings
    self.syncedAt = syncedAt
  }

  enum CodingKeys: String, CodingKey {
    case v, windows, settings
    case providerID = "provider_id"
    case workItems = "work_items"
    case activeSessionCount = "active_count"
    case syncedAt = "synced_at"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    v = try container.decode(Int.self, forKey: .v)
    providerID = try container.decode(String.self, forKey: .providerID)
    windows = try container.decode([WatchWindowPayload].self, forKey: .windows)
    includesWorkItems = container.contains(.workItems)
    workItems = try container.decodeIfPresent(
      [WorkItemPayload].self, forKey: .workItems) ?? []
    activeSessionCount = try container.decodeIfPresent(
      Int.self, forKey: .activeSessionCount)
    settings = try container.decodeIfPresent(
      WatchSettingsPayload.self, forKey: .settings)
    syncedAt = try container.decode(Int.self, forKey: .syncedAt)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(v, forKey: .v)
    try container.encode(providerID, forKey: .providerID)
    try container.encode(windows, forKey: .windows)
    if includesWorkItems {
      try container.encode(workItems, forKey: .workItems)
    }
    try container.encodeIfPresent(activeSessionCount, forKey: .activeSessionCount)
    try container.encodeIfPresent(settings, forKey: .settings)
    try container.encode(syncedAt, forKey: .syncedAt)
  }
}

public enum WatchProjectionV2 {
  /// Display priority for known window ids; everything else sorts last while
  /// keeping its snapshot order.
  private static let windowPriority = ["5h", "weekly", "monthly"]

  /// Unlike the v1 projection this accepts any provider. Freshness is the
  /// caller's decision; the projection never invents values, it only shapes
  /// the snapshot it is given.
  public static func encode(
    snapshot: QuotaSnapshot,
    workItems: [WorkItemPayload],
    activeSessionCount: Int? = nil,
    settings: WatchSettingsPayload? = nil,
    now: Date
  ) throws -> Data {
    let state = WatchFaceState(
      snapshots: [snapshot],
      workItems: workItems,
      activeSessionCount: activeSessionCount,
      capturedAt: now)
    return try encode(
      state: state,
      provider: state.providers[0],
      settings: settings)
  }

  /// Projects one provider from the complete renderer-facing state into the
  /// existing v2 wire format. A batch sync calls this once per provider.
  public static func encode(
    state: WatchFaceState,
    provider: WatchFaceProviderState,
    settings: WatchSettingsPayload? = nil,
    includesWorkItems: Bool = true
  ) throws -> Data {
    let windows =
      provider.windows
      .enumerated()
      .sorted { lhs, rhs in
        (rank(of: lhs.element.id), lhs.offset) < (rank(of: rhs.element.id), rhs.offset)
      }
      .prefix(3)
      .map { _, window in
        WatchWindowPayload(
          id: window.id,
          remainingPercent: window.remainingPercent,
          resetInSeconds: max(
            0, Int((window.resetsAt ?? state.capturedAt).timeIntervalSince(state.capturedAt))),
          windowDurationSeconds: window.durationSeconds)
      }
    let items =
      state.workItems
      .filter { WorkItemPayload.slotRange.contains($0.slot) }
      .map { item in
        WorkItemPayload(
          slot: item.slot,
          name: WorkItem.sanitizedName(item.name),
          source: item.source,
          state: item.state,
          latest: item.latest == true,
          seen: item.seen == true)
      }
      .prefix(3)
    let payload = WatchPayloadV2(
      providerID: provider.id,
      windows: Array(windows),
      workItems: Array(items),
      activeSessionCount: state.activeSessionCount.map { min(Int(UInt16.max), $0) },
      settings: settings,
      syncedAt: Int(state.capturedAt.timeIntervalSince1970),
      includesWorkItems: includesWorkItems)
    let data = try JSONEncoder().encode(payload)
    guard data.count <= 512 else {
      throw WatchProjectionError.payloadTooLarge
    }
    return data
  }

  private static func rank(of id: String) -> Int {
    windowPriority.firstIndex(of: id) ?? windowPriority.count
  }
}
