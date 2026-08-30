import Foundation
import TokenLinkCore

/// Transport-independent quota state exposed to a watch face.
public struct WatchFaceWindowState: Equatable, Sendable {
  public let id: String
  public let label: String
  public let remainingPercent: Double
  public let resetsAt: Date?

  public init(
    id: String,
    label: String,
    remainingPercent: Double,
    resetsAt: Date?
  ) {
    self.id = id
    self.label = label
    self.remainingPercent = min(100, max(0, remainingPercent))
    self.resetsAt = resetsAt
  }
}

/// One provider and all of its semantic windows before device-specific caps.
public struct WatchFaceProviderState: Equatable, Sendable {
  public let id: String
  public let windows: [WatchFaceWindowState]

  public init(id: String, windows: [WatchFaceWindowState]) {
    self.id = id
    self.windows = windows
  }

  public init(snapshot: QuotaSnapshot) {
    self.init(
      id: snapshot.provider.rawValue,
      windows: snapshot.windows.map { window in
        WatchFaceWindowState(
          id: window.id,
          label: window.label,
          remainingPercent: window.remainingPercent,
          resetsAt: window.resetsAt)
      })
  }
}

/// A renderer-facing work item. It deliberately excludes the private Mac
/// thread identifier carried by `WorkItem`.
public struct WatchFaceWorkItemState: Equatable, Sendable {
  public let slot: Int
  public let name: String
  public let source: String
  public let state: WorkItemState
  public let latest: Bool

  public init(
    slot: Int,
    name: String,
    source: String,
    state: WorkItemState,
    latest: Bool = false
  ) {
    self.slot = slot
    self.name = name
    self.source = source
    self.state = state
    self.latest = latest
  }

  public init(payload: WorkItemPayload) {
    self.init(
      slot: payload.slot,
      name: payload.name,
      source: payload.source,
      state: payload.state,
      latest: payload.latest == true)
  }
}

/// Canonical state shared by built-in and future packaged faces.
///
/// This model keeps the full semantic input. BLE-specific window/item caps,
/// relative countdown conversion, field names, and byte limits belong to the
/// protocol projection layer instead.
public struct WatchFaceState: Equatable, Sendable {
  public let providers: [WatchFaceProviderState]
  public let workItems: [WatchFaceWorkItemState]
  public let activeSessionCount: Int?
  public let capturedAt: Date

  public init(
    providers: [WatchFaceProviderState],
    workItems: [WatchFaceWorkItemState],
    activeSessionCount: Int? = nil,
    capturedAt: Date
  ) {
    self.providers = providers
    self.workItems = workItems
    self.activeSessionCount = activeSessionCount.map { max(0, $0) }
    self.capturedAt = capturedAt
  }

  public init(
    snapshots: [QuotaSnapshot],
    workItems: [WorkItemPayload],
    activeSessionCount: Int? = nil,
    capturedAt: Date
  ) {
    self.init(
      providers: snapshots.map(WatchFaceProviderState.init(snapshot:)),
      workItems: workItems.map(WatchFaceWorkItemState.init(payload:)),
      activeSessionCount: activeSessionCount,
      capturedAt: capturedAt)
  }
}
