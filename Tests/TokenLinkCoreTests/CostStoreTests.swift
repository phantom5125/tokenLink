import Foundation
import Testing

@testable import TokenLinkCore

private let openRouterAccount = UUID(
  uuidString: "00000000-0000-0000-0000-00000000C001")!

private func authoritativeSnapshot(at date: Date) -> AuthoritativeCostSnapshot {
  AuthoritativeCostSnapshot(
    provider: .openrouter,
    balances: [AccountBalance(currency: "USD", available: 42)],
    fetchedAt: date)
}

private func estimatedSnapshot(at date: Date) -> EstimatedCostSnapshot {
  EstimatedCostSnapshot(
    provider: .codex,
    period: DateInterval(start: date.addingTimeInterval(-604_800), end: date),
    lineItems: [],
    totals: [CurrencyAmount(value: 3, currency: "USD")],
    unknownModelIDs: [],
    catalogVersion: "test",
    catalogEffectiveDate: date,
    scannedAt: date)
}

@Test func costStoreKeepsAuthoritativeLastKnownGoodOnFailure() async {
  let snapshot = authoritativeSnapshot(at: Date(timeIntervalSince1970: 100))
  let store = CostStore(now: { Date(timeIntervalSince1970: 200) })

  await store.acceptAuthoritative(.success(snapshot), accountID: openRouterAccount)
  #expect(await store.authoritativeState(for: openRouterAccount).phase == .healthy)

  await store.acceptAuthoritative(
    .failure(.network("offline")),
    accountID: openRouterAccount)
  let failed = await store.authoritativeState(for: openRouterAccount)
  #expect(failed.phase == .stale)
  #expect(failed.snapshot == snapshot)
  #expect(failed.error?.kind == .network)
}

@Test func costStoreMapsInitialFailuresWithoutInventingSnapshots() async {
  let store = CostStore()
  await store.acceptAuthoritative(
    .failure(.missingCredential("no key")),
    accountID: openRouterAccount)
  await store.acceptEstimate(
    .failure(.init(kind: .process, message: "unreadable")),
    provider: .codex)

  let authoritative = await store.authoritativeState(for: openRouterAccount)
  let estimated = await store.estimatedState(for: .codex)
  #expect(authoritative.phase == .missingCredential)
  #expect(authoritative.snapshot == nil)
  #expect(estimated.phase == .error)
  #expect(estimated.snapshot == nil)
  #expect(estimated.error?.kind == .process)
}

@Test func costStoreUsesIndependentFifteenAndThirtyMinuteTTLs() async {
  let clock = CostStoreClock(Date(timeIntervalSince1970: 1_000))
  let store = CostStore(now: clock.callAsFunction)
  await store.acceptAuthoritative(
    .success(authoritativeSnapshot(at: clock.value)),
    accountID: openRouterAccount)
  await store.acceptEstimate(
    .success(estimatedSnapshot(at: clock.value)),
    provider: .codex)

  clock.value = Date(timeIntervalSince1970: 1_901)
  #expect(await store.authoritativeState(for: openRouterAccount).phase == .stale)
  #expect(await store.estimatedState(for: .codex).phase == .healthy)

  clock.value = Date(timeIntervalSince1970: 2_800)
  #expect(await store.estimatedState(for: .codex).phase == .healthy)
  clock.value = Date(timeIntervalSince1970: 2_801)
  #expect(await store.estimatedState(for: .codex).phase == .stale)
}

@Test func clearingCostStoreDoesNotRequireOrAffectProviderStore() async {
  let store = CostStore()
  await store.acceptAuthoritative(
    .success(authoritativeSnapshot(at: Date())),
    accountID: openRouterAccount)
  await store.acceptEstimate(.success(estimatedSnapshot(at: Date())), provider: .codex)

  await store.clear()

  #expect(await store.authoritativeState(for: openRouterAccount).phase == .disabled)
  #expect(await store.estimatedState(for: .codex).phase == .disabled)
}

private final class CostStoreClock: @unchecked Sendable {
  var value: Date

  init(_ value: Date) {
    self.value = value
  }

  func callAsFunction() -> Date { value }
}
