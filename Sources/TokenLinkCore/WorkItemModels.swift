import Foundation

/// Watch-face work item lifecycle, as rendered on the P2 page.
/// Raw values match the v2 payload strings; the firmware never parses them.
public enum WorkItemState: String, Codable, Sendable {
  case running
  case needsInput = "needs_input"
  case completed = "complete"
  case failed
  case unknown

  /// Unknown states from newer firmware/protocol revisions decode as
  /// `.unknown` instead of failing the whole payload (forward compatibility).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    // `completed` appeared in an early Mac-only prototype. Accept it while
    // always encoding the protocol's canonical `complete` spelling.
    self = raw == "completed" ? .completed : WorkItemState(rawValue: raw) ?? .unknown
  }

  public var isActive: Bool {
    self == .running || self == .needsInput
  }

  /// Lower values are more important on the watch's three-row Sessions page.
  /// Actionable states lead, active work follows, and terminal/unknown states
  /// yield their slot when a more useful session is available.
  public var watchDisplayPriority: Int {
    switch self {
    case .needsInput: 0
    case .failed: 1
    case .running: 2
    case .completed: 3
    case .unknown: 4
    }
  }
}

/// One agent session tracked on the Mac. `id` stays local (it is the
/// provider-side thread identifier); only `slot` goes down to the watch.
public struct WorkItem: Equatable, Sendable, Identifiable {
  public static let maxNameLength = 12

  public let id: String
  public internal(set) var slot: Int
  public var name: String
  public var source: ProviderID
  public var state: WorkItemState
  public var updatedAt: Date
  /// Mac-side rename wins over anything a poll wants to write into `name`.
  public internal(set) var isCustomNamed: Bool

  public init(
    id: String,
    slot: Int,
    name: String,
    source: ProviderID,
    state: WorkItemState,
    updatedAt: Date,
    isCustomNamed: Bool = false
  ) {
    self.id = id
    self.slot = slot
    self.name = name
    self.source = source
    self.state = state
    self.updatedAt = updatedAt
    self.isCustomNamed = isCustomNamed
  }

  /// The watch accepts at most 12 printable ASCII characters for a name.
  /// Non-ASCII content is filtered out and edges are trimmed; an empty
  /// result falls back so the firmware always gets something renderable.
  public static func sanitizedName(_ raw: String, fallback: String = "task") -> String {
    let ascii = raw.unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7F }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: ascii)
    let trimmed = String(view).trimmingCharacters(in: .whitespaces)
    let truncated = String(trimmed.prefix(Self.maxNameLength))
      .trimmingCharacters(in: .whitespaces)
    return truncated.isEmpty ? fallback : truncated
  }
}

/// One entry of the v2 payload `work_items` array (see design doc §8).
public struct WorkItemPayload: Codable, Equatable, Sendable {
  public static let slotRange = 0...2

  public let slot: Int
  public let name: String
  public let source: String
  public let state: WorkItemState
  /// Present only on the most recently updated session. Optional keeps the
  /// v2 payload compact and remains compatible with existing firmware.
  public let latest: Bool?

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
    self.latest = latest ? true : nil
  }
}

/// Tracks the three most useful work items and assigns each a stable watch
/// slot. Existing items stay in place; a new item reuses only the slot of a
/// lower-priority candidate. AppModel owns one instance and feeds it from
/// provider trackers after each quota refresh cycle.
public actor WorkItemStore {
  public static let capacity = 3

  private var storage: [String: WorkItem] = [:]
  private var reportedActiveSessionCount: Int?

  public init() {}

  /// Items sorted by slot, ready for display or payload export.
  public var items: [WorkItem] {
    storage.values.sorted { $0.slot < $1.slot }
  }

  /// Full active count reported by the provider poll. This is intentionally
  /// independent of the three display slots sent to the watch.
  public var activeSessionCount: Int {
    reportedActiveSessionCount
      ?? storage.values.filter { $0.state.isActive }.count
  }

  public func reportActiveSessionCount(_ count: Int) {
    reportedActiveSessionCount = max(0, count)
  }

  /// Inserts or refreshes a work item. New items get the lowest free slot.
  /// At capacity, needs-input and failed work outrank running work, which
  /// outranks completed and unknown work; recency breaks ties. Replacements
  /// reuse the evicted item's slot so unaffected rows do not jump around.
  @discardableResult
  public func upsert(
    id: String,
    name: String,
    source: ProviderID,
    state: WorkItemState,
    updatedAt: Date
  ) -> WorkItem? {
    let cleanName = WorkItem.sanitizedName(name)
    if var existing = storage[id] {
      existing.state = state
      existing.updatedAt = updatedAt
      if !existing.isCustomNamed {
        existing.name = cleanName
      }
      storage[id] = existing
      return existing
    }
    guard let slot = nextSlot(forNewItemState: state, updatedAt: updatedAt) else {
      return nil
    }
    let item = WorkItem(
      id: id,
      slot: slot,
      name: cleanName,
      source: source,
      state: state,
      updatedAt: updatedAt)
    storage[id] = item
    return item
  }

  /// Mac-side rename; polls never overwrite a custom name afterwards.
  public func rename(id: String, to name: String) {
    guard var existing = storage[id] else { return }
    existing.name = WorkItem.sanitizedName(name)
    existing.isCustomNamed = true
    storage[id] = existing
  }

  public func remove(id: String) {
    storage[id] = nil
  }

  /// Removes items from one provider that were absent from a complete poll.
  /// Callers must not invoke this after a partial or failed listing.
  public func removeMissing(source: ProviderID, keepingIDs: Set<String>) {
    let missingIDs = storage.values.compactMap { item in
      item.source == source && !keepingIDs.contains(item.id) ? item.id : nil
    }
    for id in missingIDs {
      storage[id] = nil
    }
  }

  public func item(forSlot slot: Int) -> WorkItem? {
    storage.values.first { $0.slot == slot }
  }

  /// Snapshot for the v2 payload `work_items` array, sorted by slot.
  public func payloadItems() -> [WorkItemPayload] {
    let latestID = storage.values.max(by: { $0.updatedAt < $1.updatedAt })?.id
    return items.map {
      WorkItemPayload(
        slot: $0.slot,
        name: $0.name,
        source: $0.source.rawValue,
        state: $0.state,
        latest: $0.id == latestID)
    }
  }

  private func nextSlot(forNewItemState state: WorkItemState, updatedAt: Date) -> Int? {
    if storage.count < Self.capacity {
      let used = Set(storage.values.map(\.slot))
      return (0..<Self.capacity).first { !used.contains($0) }
    }

    guard var lowestPriority = storage.values.first else { return nil }
    for item in storage.values.dropFirst() {
      if Self.outranks(lowestPriority, item) {
        lowestPriority = item
      }
    }
    guard Self.outranks(state: state, updatedAt: updatedAt, lowestPriority) else {
      return nil
    }
    storage[lowestPriority.id] = nil
    return lowestPriority.slot
  }

  private static func outranks(_ lhs: WorkItem, _ rhs: WorkItem) -> Bool {
    outranks(state: lhs.state, updatedAt: lhs.updatedAt, rhs)
  }

  private static func outranks(
    state: WorkItemState,
    updatedAt: Date,
    _ rhs: WorkItem
  ) -> Bool {
    if state.watchDisplayPriority != rhs.state.watchDisplayPriority {
      return state.watchDisplayPriority < rhs.state.watchDisplayPriority
    }
    return updatedAt > rhs.updatedAt
  }
}
