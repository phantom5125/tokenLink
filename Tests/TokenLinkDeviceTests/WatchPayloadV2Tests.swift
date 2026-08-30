import Foundation
import Testing

@testable import TokenLinkCore
@testable import TokenLinkDevice

private func window(
  _ id: String,
  remaining: Double = 50,
  resetsAt: Date? = nil
) -> QuotaWindow {
  QuotaWindow(
    id: id, label: id, usedPercent: nil, remainingPercent: remaining,
    remainingCount: nil, limitCount: nil, resetsAt: resetsAt)
}

private func snapshot(
  provider: ProviderID = .codex,
  windows: [QuotaWindow]
) -> QuotaSnapshot {
  QuotaSnapshot(
    provider: provider, planLabel: nil, windows: windows,
    source: .localAppServer, fetchedAt: Date(timeIntervalSince1970: 1_000))
}

@Test func payloadV2RoundTripsWithSettings() throws {
  let payload = WatchPayloadV2(
    providerID: "codex",
    windows: [
      WatchWindowPayload(id: "5h", remainingPercent: 72, resetInSeconds: 900)
    ],
    workItems: [
      WorkItemPayload(slot: 0, name: "review", source: "codex", state: .running),
      WorkItemPayload(
        slot: 1, name: "fix-ci", source: "codex", state: .needsInput, seen: true),
    ],
    activeSessionCount: 4,
    settings: WatchSettingsPayload(theme: "pet", wake: "tap", hourFormat: "h24"),
    syncedAt: 1_787_616_000)
  let data = try JSONEncoder().encode(payload)
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded == payload)
  let object = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["v"] as? Int == 2)
  #expect(object["active_count"] as? Int == 4)
  let workItems = try #require(object["work_items"] as? [[String: Any]])
  #expect(workItems[0]["seen"] == nil)
  #expect(workItems[1]["seen"] as? Bool == true)
  let settings = try #require(object["settings"] as? [String: Any])
  #expect(settings["theme"] as? String == "pet")
  #expect(settings["wake"] as? String == "tap")
  #expect(settings["hour_format"] as? String == "h24")
}

@Test func projectionCarriesFullActiveCountBeyondDisplayedItems() throws {
  let data = try WatchProjectionV2.encode(
    snapshot: snapshot(windows: [window("primary")]),
    workItems: [
      WorkItemPayload(slot: 0, name: "latest", source: "codex", state: .completed)
    ],
    activeSessionCount: 7,
    now: Date(timeIntervalSince1970: 1_000))
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded.workItems.count == 1)
  #expect(decoded.activeSessionCount == 7)
}

@Test func payloadV2OmitsSettingsWhenAbsent() throws {
  let payload = WatchPayloadV2(
    providerID: "kimi", windows: [], workItems: [], syncedAt: 1)
  let data = try JSONEncoder().encode(payload)
  let object = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["settings"] == nil)
  #expect(object["active_count"] == nil)
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded.settings == nil)
  #expect(decoded.activeSessionCount == nil)
}

@Test func payloadV2IgnoresUnknownFieldsForForwardCompatibility() throws {
  let json = """
    {
      "v": 2,
      "provider_id": "codex",
      "windows": [
        {"id": "5h", "remaining_percent": 72, "reset_in_seconds": 900, "extra": true}
      ],
      "work_items": [
        {"slot": 0, "name": "review", "source": "codex", "state": "paused", "x": 1}
      ],
      "synced_at": 100,
      "future_field": {"nested": [1, 2, 3]}
    }
    """
  let decoded = try JSONDecoder().decode(
    WatchPayloadV2.self, from: Data(json.utf8))
  #expect(decoded.providerID == "codex")
  #expect(decoded.windows.count == 1)
  #expect(decoded.workItems.first?.state == .unknown)
}

@Test func projectionOrdersWindowsByPriorityAndCapsAtThree() throws {
  let now = Date(timeIntervalSince1970: 1_000)
  let data = try WatchProjectionV2.encode(
    snapshot: snapshot(windows: [
      window("monthly", resetsAt: now.addingTimeInterval(300)),
      window("custom", resetsAt: now.addingTimeInterval(100)),
      window("weekly", resetsAt: now.addingTimeInterval(200)),
      window("5h", resetsAt: now.addingTimeInterval(50)),
    ]),
    workItems: [],
    now: now)
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded.windows.map(\.id) == ["5h", "weekly", "monthly"])
  #expect(decoded.windows.map(\.resetInSeconds) == [50, 200, 300])
}

@Test func projectionClampsResetSecondsToNonNegative() throws {
  let now = Date(timeIntervalSince1970: 1_000)
  let data = try WatchProjectionV2.encode(
    snapshot: snapshot(windows: [
      window("5h", resetsAt: now.addingTimeInterval(-30)),
      window("weekly", resetsAt: nil),
    ]),
    workItems: [],
    now: now)
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded.windows.map(\.resetInSeconds) == [0, 0])
}

@Test func projectionAcceptsNonCodexProviders() throws {
  let data = try WatchProjectionV2.encode(
    snapshot: snapshot(provider: .kimi, windows: [window("primary")]),
    workItems: [],
    now: Date(timeIntervalSince1970: 1_000))
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded.providerID == "kimi")
}

@Test func projectionSanitizesWorkItemNamesAndSlots() throws {
  let now = Date(timeIntervalSince1970: 1_000)
  let data = try WatchProjectionV2.encode(
    snapshot: snapshot(windows: [window("primary")]),
    workItems: [
      WorkItemPayload(slot: 0, name: "averylongworkitemname", source: "codex", state: .running),
      WorkItemPayload(slot: 1, name: "修复-ci", source: "codex", state: .failed),
      WorkItemPayload(slot: 2, name: "中文中", source: "codex", state: .completed),
      WorkItemPayload(slot: 3, name: "out", source: "codex", state: .running),
      WorkItemPayload(slot: -1, name: "neg", source: "codex", state: .running),
    ],
    now: now)
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  // Slots 0-2 are kept (slot 3 and -1 are out of range); a name with no
  // printable ASCII falls back to "task" instead of dropping the item.
  #expect(decoded.workItems.count == 3)
  #expect(decoded.workItems[0].name == "averylongwor")
  #expect(decoded.workItems[1].name == "-ci")
  #expect(decoded.workItems[2].name == "task")
}

@Test func projectionCapsWorkItemsAtThree() throws {
  let now = Date(timeIntervalSince1970: 1_000)
  let data = try WatchProjectionV2.encode(
    snapshot: snapshot(windows: [window("primary")]),
    workItems: (0...4).map {
      WorkItemPayload(slot: $0 % 3, name: "w\($0)", source: "codex", state: .running)
    },
    now: now)
  let decoded = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(decoded.workItems.count == 3)
  #expect(data.count <= 512)
}

@Test func projectionRejectsPayloadsBeyond512Bytes() {
  let bloated = window(String(repeating: "x", count: 600))
  #expect(throws: WatchProjectionError.payloadTooLarge) {
    try WatchProjectionV2.encode(
      snapshot: snapshot(windows: [bloated]),
      workItems: [],
      now: Date(timeIntervalSince1970: 1_000))
  }
}
