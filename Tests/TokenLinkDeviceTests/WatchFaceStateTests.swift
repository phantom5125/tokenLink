import Foundation
import Testing
import TokenLinkCore
import TokenLinkDevice

private func faceStateSnapshot(
  _ provider: ProviderID,
  windows: [QuotaWindow]
) -> QuotaSnapshot {
  QuotaSnapshot(
    provider: provider,
    planLabel: nil,
    windows: windows,
    source: .localAppServer,
    fetchedAt: Date(timeIntervalSince1970: 900))
}

private func faceStateWindow(
  _ id: String,
  label: String,
  remaining: Double,
  resetsAt: Date? = nil,
  durationSeconds: Int? = nil
) -> QuotaWindow {
  QuotaWindow(
    id: id,
    label: label,
    usedPercent: nil,
    remainingPercent: remaining,
    remainingCount: nil,
    limitCount: nil,
    resetsAt: resetsAt,
    durationSeconds: durationSeconds)
}

@Test func canonicalFaceStatePreservesSemanticDataBeforeWireCaps() {
  let capturedAt = Date(timeIntervalSince1970: 1_000)
  let state = WatchFaceState(
    snapshots: [
      faceStateSnapshot(
        .codex,
        windows: [
          faceStateWindow("5h", label: "Five hours", remaining: 72),
          faceStateWindow("weekly", label: "Weekly", remaining: 61),
          faceStateWindow("monthly", label: "Monthly", remaining: 55),
          faceStateWindow(
            "custom", label: "Custom", remaining: 40,
            durationSeconds: 12 * 3_600),
        ]),
      faceStateSnapshot(
        .kimi,
        windows: [faceStateWindow("weekly", label: "Week", remaining: 80)]),
    ],
    workItems: [
      WorkItemPayload(
        slot: 0, name: "review", source: "codex", state: .needsInput, latest: true,
        seen: true)
    ],
    activeSessionCount: 70_000,
    capturedAt: capturedAt)

  #expect(state.providers.map(\.id) == ["codex", "kimi"])
  #expect(state.providers[0].windows.count == 4)
  #expect(state.providers[0].windows[0].label == "Five hours")
  #expect(state.providers[0].windows[0].durationSeconds == 5 * 3_600)
  #expect(state.providers[0].windows[1].durationSeconds == 7 * 86_400)
  #expect(state.providers[0].windows[3].durationSeconds == 12 * 3_600)
  #expect(state.workItems[0].state == .needsInput)
  #expect(state.workItems[0].latest)
  #expect(state.workItems[0].seen)
  #expect(state.activeSessionCount == 70_000)
  #expect(state.capturedAt == capturedAt)
}

@Test func canonicalProjectionKeepsExistingV2WireSemantics() throws {
  let now = Date(timeIntervalSince1970: 1_000)
  let snapshot = faceStateSnapshot(
    .codex,
    windows: [
      faceStateWindow(
        "monthly", label: "Month", remaining: 60,
        resetsAt: now.addingTimeInterval(300)),
      faceStateWindow(
        "5h", label: "Five hours", remaining: 72,
        resetsAt: now.addingTimeInterval(50)),
      faceStateWindow(
        "weekly", label: "Week", remaining: 65,
        resetsAt: now.addingTimeInterval(200)),
      faceStateWindow(
        "custom", label: "Custom", remaining: 40,
        resetsAt: now.addingTimeInterval(10)),
    ])
  let items = [
    WorkItemPayload(
      slot: 0, name: "averylongworkitemname", source: "codex", state: .running)
  ]
  let settings = WatchSettingsPayload(theme: "pet", wake: "tap", hourFormat: "h24")
  let state = WatchFaceState(
    snapshots: [snapshot],
    workItems: items,
    activeSessionCount: 70_000,
    capturedAt: now)

  let data = try WatchProjectionV2.encode(
    state: state,
    provider: state.providers[0],
    settings: settings)
  let payload = try JSONDecoder().decode(WatchPayloadV2.self, from: data)

  #expect(payload.providerID == "codex")
  #expect(payload.windows.map(\.id) == ["5h", "weekly", "monthly"])
  #expect(payload.windows.map(\.resetInSeconds) == [50, 200, 300])
  #expect(payload.windows.map(\.windowDurationSeconds) == [18_000, 604_800, 2_592_000])
  #expect(payload.workItems[0].name == "averylongwor")
  #expect(payload.activeSessionCount == Int(UInt16.max))
  #expect(payload.settings == settings)
  #expect(payload.syncedAt == 1_000)
}
