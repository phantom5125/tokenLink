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

/// Tracks the (at most three) most recently active work items and assigns
/// each a stable watch slot. AppModel owns one instance and feeds it from
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

  /// Inserts or refreshes a work item. New items get the lowest free slot;
  /// at capacity the least recently active item is evicted, and an incoming
  /// item older than everything already stored is dropped (returns nil).
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
    guard let slot = nextSlot(forNewItemUpdatedAt: updatedAt) else { return nil }
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

  private func nextSlot(forNewItemUpdatedAt updatedAt: Date) -> Int? {
    if storage.count < Self.capacity {
      let used = Set(storage.values.map(\.slot))
      return (0..<Self.capacity).first { !used.contains($0) }
    }
    guard
      let oldest = storage.values.min(by: { $0.updatedAt < $1.updatedAt }),
      updatedAt > oldest.updatedAt
    else { return nil }
    storage[oldest.id] = nil
    return oldest.slot
  }
}
