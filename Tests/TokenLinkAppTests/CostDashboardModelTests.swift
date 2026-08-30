import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkApp

private let costAccount = UUID(
  uuidString: "00000000-0000-0000-0000-00000000D001")!

private actor CostLoaderProbe {
  private(set) var authoritativeCalls = 0
  private(set) var estimateCalls = 0
  var authoritativeResult: Result<AuthoritativeCostSnapshot, ProviderFailure>
  var estimateResult: Result<EstimatedCostSnapshot, ProviderFailure>
  let delay: Duration?

  init(
    authoritativeResult: Result<AuthoritativeCostSnapshot, ProviderFailure>,
    estimateResult: Result<EstimatedCostSnapshot, ProviderFailure>,
    delay: Duration? = nil
  ) {
    self.authoritativeResult = authoritativeResult
    self.estimateResult = estimateResult
    self.delay = delay
  }

  func loadAuthoritative(
    _ source: AuthoritativeCostSource
  ) async -> Result<AuthoritativeCostSnapshot, ProviderFailure> {
    authoritativeCalls += 1
    if let delay { try? await Task.sleep(for: delay) }
    return authoritativeResult
  }

  func loadEstimate(
    _ provider: ProviderID
  ) async -> Result<EstimatedCostSnapshot, ProviderFailure> {
    estimateCalls += 1
    if let delay { try? await Task.sleep(for: delay) }
    return estimateResult
  }
}

private actor PeriodCostLoaderProbe {
  private(set) var calls = 0
  let date: Date

  init(date: Date) {
    self.date = date
  }

  func load(_ provider: ProviderID) -> Result<EstimatedCostPeriodCollection, ProviderFailure> {
    calls += 1
    let snapshots = Dictionary(
      uniqueKeysWithValues: CostDisplayPeriod.allCases.map { period in
        let value: Decimal =
          switch period {
          case .today: 1
          case .week: 2
          case .month: 3
          }
        return (
          period,
          EstimatedCostSnapshot(
            provider: provider,
            period: period.interval(endingAt: date),
            lineItems: [],
            totals: [CurrencyAmount(value: value, currency: "USD")],
            unknownModelIDs: [],
            catalogVersion: "period-test",
            catalogEffectiveDate: date,
            scannedAt: date)
        )
      })
    return .success(EstimatedCostPeriodCollection(provider: provider, snapshots: snapshots))
  }
}

private func dashboardAuthoritativeSnapshot(at date: Date) -> AuthoritativeCostSnapshot {
  AuthoritativeCostSnapshot(
    provider: .openrouter,
    balances: [AccountBalance(currency: "USD", available: 75)],
    fetchedAt: date)
}

private func dashboardEstimateSnapshot(at date: Date) -> EstimatedCostSnapshot {
  EstimatedCostSnapshot(
    provider: .codex,
    period: DateInterval(start: date.addingTimeInterval(-604_800), end: date),
    lineItems: [],
    totals: [CurrencyAmount(value: 2, currency: "USD")],
    unknownModelIDs: [],
    catalogVersion: "test",
    catalogEffectiveDate: date,
    scannedAt: date)
}

@MainActor @Test func disabledCostDashboardPerformsNoWork() async {
  let date = Date(timeIntervalSince1970: 1_000)
  let probe = CostLoaderProbe(
    authoritativeResult: .success(dashboardAuthoritativeSnapshot(at: date)),
    estimateResult: .success(dashboardEstimateSnapshot(at: date)))
  let model = makeDashboard(enabled: false, probe: probe, now: date)

  await model.loadIfNeeded()
  await model.refreshCosts(force: true)

  #expect(await probe.authoritativeCalls == 0)
  #expect(await probe.estimateCalls == 0)
  #expect(model.authoritativeRows.isEmpty)
  #expect(model.estimateRows.isEmpty)
}

@MainActor @Test func costDashboardLoadsOnceBeforeTTLAndForceBypassesTTL() async {
  let date = Date(timeIntervalSince1970: 1_000)
  let probe = CostLoaderProbe(
    authoritativeResult: .success(dashboardAuthoritativeSnapshot(at: date)),
    estimateResult: .success(dashboardEstimateSnapshot(at: date)))
  let model = makeDashboard(enabled: true, probe: probe, now: date)

  await model.loadIfNeeded()
  await model.loadIfNeeded()
  #expect(await probe.authoritativeCalls == 1)
  #expect(await probe.estimateCalls == 1)
  #expect(model.authoritativeRows.first?.state.phase == .healthy)
  #expect(model.estimateRows.first?.state.phase == .healthy)

  await model.refreshCosts(force: true)
  #expect(await probe.authoritativeCalls == 2)
  #expect(await probe.estimateCalls == 2)
}

@MainActor @Test func concurrentCostDashboardRefreshesCoalesce() async {
  let date = Date(timeIntervalSince1970: 1_000)
  let probe = CostLoaderProbe(
    authoritativeResult: .success(dashboardAuthoritativeSnapshot(at: date)),
    estimateResult: .success(dashboardEstimateSnapshot(at: date)),
    delay: .milliseconds(40))
  let model = makeDashboard(enabled: true, probe: probe, now: date)

  async let first: Void = model.refreshCosts(force: true)
  async let second: Void = model.refreshCosts(force: true)
  _ = await (first, second)

  #expect(await probe.authoritativeCalls == 1)
  #expect(await probe.estimateCalls == 1)
  #expect(model.isRefreshing == false)
}

@MainActor @Test func costDashboardPublishesEachSourceAsItFinishes() async throws {
  // Catches a fast authoritative result being hidden behind a slower local scan.
  let date = Date(timeIntervalSince1970: 1_000)
  let model = CostDashboardModel(
    enabled: true,
    authoritativeSources: [
      AuthoritativeCostSource(accountID: costAccount, provider: .openrouter)
    ],
    estimateProviders: [.codex],
    store: CostStore(now: { date }),
    authoritativeLoader: { _ in
      .success(dashboardAuthoritativeSnapshot(at: date))
    },
    estimateLoader: { _ in
      try? await Task.sleep(for: .milliseconds(400))
      return .success(dashboardEstimateSnapshot(at: date))
    },
    now: { date })

  let refresh = Task { await model.refreshCosts(force: true) }
  for _ in 0..<50 {
    if model.authoritativeRows.first?.state.phase == .healthy { break }
    try await Task.sleep(for: .milliseconds(5))
  }

  #expect(model.authoritativeRows.first?.state.phase == .healthy)
  #expect(model.isRefreshing)
  await refresh.value
  #expect(model.estimateRows.first?.state.phase == .healthy)
}

@MainActor @Test func sourceFailuresRemainIndependentAndDisableClearsRows() async {
  let date = Date(timeIntervalSince1970: 1_000)
  let probe = CostLoaderProbe(
    authoritativeResult: .failure(.authentication("rejected")),
    estimateResult: .success(dashboardEstimateSnapshot(at: date)))
  let model = makeDashboard(enabled: true, probe: probe, now: date)

  await model.loadIfNeeded()

  #expect(model.authoritativeRows.first?.state.phase == .error)
  #expect(model.authoritativeRows.first?.state.error?.kind == .authentication)
  #expect(model.estimateRows.first?.state.phase == .healthy)
  #expect(model.diagnosticMetadata.sources.count == 2)

  await model.disable()
  #expect(model.isEnabled == false)
  #expect(model.isRefreshing == false)
  #expect(model.authoritativeRows.isEmpty)
  #expect(model.estimateRows.isEmpty)
  #expect(model.diagnosticMetadata.sources.isEmpty)
}

@MainActor @Test func disablingCostDashboardCancelsInFlightPresentationUpdates() async {
  let date = Date(timeIntervalSince1970: 1_000)
  let probe = CostLoaderProbe(
    authoritativeResult: .success(dashboardAuthoritativeSnapshot(at: date)),
    estimateResult: .success(dashboardEstimateSnapshot(at: date)),
    delay: .seconds(1))
  let model = makeDashboard(enabled: true, probe: probe, now: date)

  let refresh = Task { await model.refreshCosts(force: true) }
  for _ in 0..<100 {
    if await probe.authoritativeCalls > 0, await probe.estimateCalls > 0 { break }
    await Task.yield()
  }
  await model.disable()
  await refresh.value

  #expect(model.isEnabled == false)
  #expect(model.isRefreshing == false)
  #expect(model.authoritativeRows.isEmpty)
  #expect(model.estimateRows.isEmpty)
}

@MainActor @Test func costDashboardAgesVisibleRowsAtTTLWithoutAnotherLoad() async throws {
  // Catches copied presentation rows remaining healthy forever while Costs stays open.
  let loadedAt = Date()
  let probe = CostLoaderProbe(
    authoritativeResult: .success(
      dashboardAuthoritativeSnapshot(
        at: loadedAt.addingTimeInterval(-CostStore.authoritativeTTL + 0.3))),
    estimateResult: .success(
      dashboardEstimateSnapshot(
        at: loadedAt.addingTimeInterval(-CostStore.estimateTTL + 0.3))))
  let model = CostDashboardModel(
    enabled: true,
    authoritativeSources: [
      AuthoritativeCostSource(accountID: costAccount, provider: .openrouter)
    ],
    estimateProviders: [.codex],
    store: CostStore(),
    authoritativeLoader: { await probe.loadAuthoritative($0) },
    estimateLoader: { await probe.loadEstimate($0) })

  await model.loadIfNeeded()
  #expect(model.authoritativeRows.first?.state.phase == .healthy)
  #expect(model.estimateRows.first?.state.phase == .healthy)

  try await Task.sleep(for: .milliseconds(600))

  #expect(model.authoritativeRows.first?.state.phase == .stale)
  #expect(model.estimateRows.first?.state.phase == .stale)
}

@MainActor @Test func changingDisplayPeriodUsesCachedSnapshotsWithoutReloading() async {
  let date = Date(timeIntervalSince1970: 1_788_199_200)
  let probe = PeriodCostLoaderProbe(date: date)
  let model = CostDashboardModel(
    enabled: true,
    selectedPeriod: .week,
    authoritativeSources: [],
    estimateProviders: [.codex],
    store: CostStore(now: { date }),
    authoritativeLoader: { _ in
      .failure(.configuration("Unexpected authoritative request."))
    },
    periodEstimateLoader: { await probe.load($0) },
    now: { date })

  await model.loadIfNeeded()
  #expect(model.estimateRows.first?.state.snapshot?.totals.first?.value == 2)

  await model.setDisplayPeriod(.today)
  #expect(model.estimateRows.first?.state.snapshot?.totals.first?.value == 1)
  await model.setDisplayPeriod(.month)
  #expect(model.estimateRows.first?.state.snapshot?.totals.first?.value == 3)
  #expect(await probe.calls == 1)
}

@MainActor private func makeDashboard(
  enabled: Bool,
  probe: CostLoaderProbe,
  now: Date
) -> CostDashboardModel {
  let store = CostStore(now: { now })
  return CostDashboardModel(
    enabled: enabled,
    authoritativeSources: [
      AuthoritativeCostSource(accountID: costAccount, provider: .openrouter)
    ],
    estimateProviders: [.codex],
    store: store,
    authoritativeLoader: { await probe.loadAuthoritative($0) },
    estimateLoader: { await probe.loadEstimate($0) },
    now: { now })
}
