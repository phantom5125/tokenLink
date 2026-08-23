import Foundation
import Testing

@testable import TokenLinkCore

private struct StubProvider: QuotaProvider {
  let id: ProviderID
  let result: Result<QuotaSnapshot, ProviderFailure>
  func fetch() async -> Result<QuotaSnapshot, ProviderFailure> { result }
}

@Test func failedRefreshKeepsLastKnownGoodAndMarksStale() async {
  let date = Date(timeIntervalSince1970: 100)
  let snapshot = QuotaSnapshot(
    provider: .kimi, planLabel: nil,
    windows: [
      .init(
        id: "5h", label: "5 hours", usedPercent: 40,
        remainingPercent: 60, remainingCount: nil, limitCount: nil, resetsAt: nil)
    ],
    source: .apiKey, fetchedAt: date)
  let store = ProviderStore(now: { Date(timeIntervalSince1970: 1_000) })
  await store.accept(.success(snapshot), provider: .kimi)
  await store.accept(.failure(.network("offline")), provider: .kimi)
  let state = await store.state(for: .kimi)
  #expect(state.snapshot == snapshot)
  #expect(state.phase == .stale)
  #expect(state.error?.kind == .network)
}

@Test func successfulSnapshotAgesFromHealthyToStale() async {
  let snapshot = QuotaSnapshot(
    provider: .glm, planLabel: nil,
    windows: [
      .init(
        id: "5h", label: "5 hours", usedPercent: 10,
        remainingPercent: 90, remainingCount: nil, limitCount: nil, resetsAt: nil)
    ],
    source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 100))
  let store = ProviderStore(now: { Date(timeIntervalSince1970: 701) })
  await store.accept(.success(snapshot), provider: .glm)
  #expect(await store.state(for: .glm, refreshIntervalSeconds: 300).phase == .stale)
}
