import Foundation
import Testing
import TokenLinkCore
import TokenLinkDevice

@testable import TokenLinkApp

private func policySnapshot(_ provider: ProviderID, remaining: Double) -> QuotaSnapshot {
  QuotaSnapshot(
    provider: provider,
    planLabel: nil,
    windows: [
      QuotaWindow(
        id: "primary",
        label: "Primary",
        usedPercent: 100 - remaining,
        remainingPercent: remaining,
        remainingCount: nil,
        limitCount: nil,
        resetsAt: Date(timeIntervalSince1970: 500))
    ],
    source: provider == .codex ? .localAppServer : .apiKey,
    fetchedAt: Date(timeIntervalSince1970: 100))
}

@Test func v1PolicyOnlyProjectsCodex() throws {
  let decision = try #require(
    WatchSyncPolicy.nextPayload(
      negotiated: .v1,
      candidates: [
        (.kimi, policySnapshot(.kimi, remaining: 40)),
        (.codex, policySnapshot(.codex, remaining: 72)),
      ],
      settings: WatchSettings(syncedProviders: [.codex, .kimi]),
      workItems: [],
      rotationCursor: 0,
      now: Date(timeIntervalSince1970: 200)))

  #expect(decision.provider == .codex)
  #expect(decision.nextCursor == 0)
  let object = try #require(
    JSONSerialization.jsonObject(with: decision.data) as? [String: Any])
  #expect(object["remaining_percent"] as? Double == 72)
  #expect(object["v"] == nil)
}

@Test func v2PolicyRotatesProvidersAndCarriesSettings() throws {
  let candidates = [
    (ProviderID.kimi, policySnapshot(.kimi, remaining: 40)),
    (ProviderID.minimax, policySnapshot(.minimax, remaining: 65)),
  ]
  let settings = WatchSettings(
    syncedProviders: [.kimi, .minimax],
    faceID: .pet,
    wakeMode: .tap,
    hourFormat: .h24)

  let first = try #require(
    WatchSyncPolicy.nextPayload(
      negotiated: .v2(WatchCapabilities(protocolVersions: [1, 2])),
      candidates: candidates,
      settings: settings,
      workItems: [],
      rotationCursor: 0,
      now: Date(timeIntervalSince1970: 200)))
  let second = try #require(
    WatchSyncPolicy.nextPayload(
      negotiated: .v2(WatchCapabilities(protocolVersions: [1, 2])),
      candidates: candidates,
      settings: settings,
      workItems: [],
      rotationCursor: first.nextCursor,
      now: Date(timeIntervalSince1970: 200)))

  #expect(first.provider == .kimi)
  #expect(second.provider == .minimax)
  #expect(second.nextCursor == 2)
  let payload = try JSONDecoder().decode(WatchPayloadV2.self, from: first.data)
  #expect(payload.settings == WatchSettingsPayload(theme: "pet", wake: "tap", hourFormat: "h24"))
}

@Test func v2BatchIncludesEveryProviderInOneRefresh() throws {
  let candidates = [
    (ProviderID.codex, policySnapshot(.codex, remaining: 72)),
    (ProviderID.kimi, policySnapshot(.kimi, remaining: 40)),
    (ProviderID.glm, policySnapshot(.glm, remaining: 55)),
  ]

  let decisions = WatchSyncPolicy.payloads(
    negotiated: .v2(WatchCapabilities(protocolVersions: [1, 2])),
    candidates: candidates,
    settings: WatchSettings(syncedProviders: Set(candidates.map(\.0))),
    workItems: [],
    activeSessionCount: 6,
    now: Date(timeIntervalSince1970: 200))

  #expect(decisions.map(\.provider) == [.codex, .kimi, .glm])
  let payloads = try decisions.map { try JSONDecoder().decode(WatchPayloadV2.self, from: $0.data) }
  #expect(payloads.map(\.providerID) == ["codex", "kimi", "glm"])
  #expect(payloads.allSatisfy { $0.activeSessionCount == 6 })
}

@Test func v2BatchDoesNotDropProvidersWhenSessionsMakeCombinedPayloadsTooLarge() throws {
  let now = Date(timeIntervalSince1970: 200)
  let candidates: [(ProviderID, QuotaSnapshot)] = [
    .codex, .kimi, .minimax,
  ].map { provider in
    (
      provider,
      QuotaSnapshot(
        provider: provider,
        planLabel: nil,
        windows: [
          QuotaWindow(
            id: "5h", label: "5 hours", usedPercent: 20,
            remainingPercent: 80, remainingCount: nil, limitCount: nil,
            resetsAt: now.addingTimeInterval(1_000)),
          QuotaWindow(
            id: "weekly", label: "Weekly", usedPercent: 30,
            remainingPercent: 70, remainingCount: nil, limitCount: nil,
            resetsAt: now.addingTimeInterval(2_000)),
        ],
        source: provider == .codex ? .localAppServer : .apiKey,
        fetchedAt: now))
  }
  let workItems = (0..<3).map { slot in
    WorkItemPayload(
      slot: slot,
      name: "ABCDEFGHIJKL",
      source: "12345678",
      state: .needsInput,
      latest: true,
      seen: true)
  }

  let decisions = WatchSyncPolicy.payloads(
    negotiated: .v2(WatchCapabilities(protocolVersions: [1, 2])),
    candidates: candidates,
    settings: WatchSettings(syncedProviders: Set(candidates.map(\.0))),
    workItems: workItems,
    activeSessionCount: 12,
    now: now)
  let payloads = try decisions.map {
    try JSONDecoder().decode(WatchPayloadV2.self, from: $0.data)
  }

  #expect(Set(payloads.map(\.providerID)) == Set(["codex", "kimi", "minimax"]))
  #expect(payloads.filter(\.includesWorkItems).count == 1)
  #expect(payloads.first(where: \.includesWorkItems)?.workItems.count == 3)
  #expect(decisions.allSatisfy { $0.data.count <= 512 })
}
