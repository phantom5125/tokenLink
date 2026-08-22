import Foundation
import Testing

@testable import TokenLinkCore

private struct StubProvider: QuotaProvider {
  let id: ProviderID
  let result: Result<QuotaSnapshot, ProviderFailure>

  func fetch() async -> Result<QuotaSnapshot, ProviderFailure> { result }
}

private let kimiAccount = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let glmAccount = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
private let codexAccount = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!

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
  await store.accept(.success(snapshot), accountID: kimiAccount)
  await store.accept(.failure(.network("offline")), accountID: kimiAccount)
  let state = await store.state(for: kimiAccount)
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
  await store.accept(.success(snapshot), accountID: glmAccount)
  #expect(await store.state(for: glmAccount, refreshIntervalSeconds: 300).phase == .stale)
}

@Test func failedCachedSnapshotExpiresAfterTwentyFourHours() async {
  let snapshot = QuotaSnapshot(
    provider: .kimi, planLabel: nil,
    windows: [
      .init(
        id: "weekly", label: "Weekly", usedPercent: 25,
        remainingPercent: 75, remainingCount: nil, limitCount: nil, resetsAt: nil)
    ],
    source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 100))
  let store = ProviderStore(now: { Date(timeIntervalSince1970: 86_501) })
  await store.accept(.success(snapshot), accountID: kimiAccount)
  await store.accept(.failure(.network("offline")), accountID: kimiAccount)

  let state = await store.state(for: kimiAccount)

  #expect(state.phase == .error)
  #expect(state.snapshot == snapshot)
  #expect(state.error?.kind == .timeout)
}

@Test func allStatesAppliesConfiguredAgeThreshold() async {
  let snapshot = QuotaSnapshot(
    provider: .glm, planLabel: nil,
    windows: [
      .init(
        id: "5h", label: "5 hours", usedPercent: 10,
        remainingPercent: 90, remainingCount: nil, limitCount: nil, resetsAt: nil)
    ],
    source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 100))
  let store = ProviderStore(now: { Date(timeIntervalSince1970: 701) })
  await store.accept(.success(snapshot), accountID: glmAccount)

  let states = await store.allStates(refreshIntervalSeconds: 300)

  #expect(states[glmAccount]?.phase == .stale)
}

@Test func accountsOfTheSameProviderKeepIndependentStates() async {
  let secondKimiAccount = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
  let snapshot = QuotaSnapshot(
    provider: .kimi, planLabel: nil,
    windows: [
      .init(
        id: "5h", label: "5 hours", usedPercent: 40,
        remainingPercent: 60, remainingCount: nil, limitCount: nil, resetsAt: nil)
    ],
    source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 100))
  let store = ProviderStore(now: { Date(timeIntervalSince1970: 200) })
  await store.accept(.success(snapshot), accountID: kimiAccount)
  await store.accept(
    .failure(.missingCredential("no key")), accountID: secondKimiAccount)

  #expect(await store.state(for: kimiAccount).phase == .healthy)
  #expect(await store.state(for: secondKimiAccount).phase == .missingCredential)
}

@Test func refreshCoordinatorFetchesProvidersConcurrently() async {
  let snapshot = QuotaSnapshot(
    provider: .codex, planLabel: nil,
    windows: [
      .init(
        id: "primary", label: "Primary", usedPercent: 20,
        remainingPercent: 80, remainingCount: nil, limitCount: nil, resetsAt: nil)
    ],
    source: .localAppServer, fetchedAt: Date())
  let store = ProviderStore()
  let coordinator = RefreshCoordinator(
    providers: [
      AccountProvider(
        accountID: codexAccount,
        provider: StubProvider(id: .codex, result: .success(snapshot)))
    ],
    store: store)

  await coordinator.refreshAll()

  #expect(await store.state(for: codexAccount).snapshot == snapshot)
}
