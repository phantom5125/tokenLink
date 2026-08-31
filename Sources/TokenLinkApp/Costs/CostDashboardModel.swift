import Foundation
import Observation
import TokenLinkCore

public struct AuthoritativeCostSource: Equatable, Hashable, Sendable {
  public let accountID: UUID
  public let provider: ProviderID

  public init(accountID: UUID, provider: ProviderID) {
    self.accountID = accountID
    self.provider = provider
  }
}

public struct AuthoritativeCostRow: Identifiable, Equatable, Sendable {
  public var id: UUID { source.accountID }
  public let source: AuthoritativeCostSource
  public let state: AuthoritativeCostState

  public init(source: AuthoritativeCostSource, state: AuthoritativeCostState) {
    self.source = source
    self.state = state
  }
}

public struct EstimatedCostRow: Identifiable, Equatable, Sendable {
  public var id: ProviderID { provider }
  public let provider: ProviderID
  public let state: EstimatedCostState

  public init(provider: ProviderID, state: EstimatedCostState) {
    self.provider = provider
    self.state = state
  }
}

public enum CostDiagnosticSourceKind: String, Equatable, Sendable {
  case authoritative
  case estimate
}

public struct CostDiagnosticSourceMetadata: Equatable, Sendable {
  public let provider: ProviderID
  public let kind: CostDiagnosticSourceKind
  public let phase: ProviderPhase
  public let errorKind: ProviderErrorKind?
  public let updatedAt: Date?
  public let catalogVersion: String?

  public init(
    provider: ProviderID,
    kind: CostDiagnosticSourceKind,
    phase: ProviderPhase,
    errorKind: ProviderErrorKind?,
    updatedAt: Date?,
    catalogVersion: String? = nil
  ) {
    self.provider = provider
    self.kind = kind
    self.phase = phase
    self.errorKind = errorKind
    self.updatedAt = updatedAt
    self.catalogVersion = catalogVersion
  }
}

public struct CostDiagnosticMetadata: Equatable, Sendable {
  public let isRefreshing: Bool
  public let lastRefreshAt: Date?
  public let sources: [CostDiagnosticSourceMetadata]

  public init(
    isRefreshing: Bool,
    lastRefreshAt: Date?,
    sources: [CostDiagnosticSourceMetadata]
  ) {
    self.isRefreshing = isRefreshing
    self.lastRefreshAt = lastRefreshAt
    self.sources = sources
  }
}

@MainActor
@Observable
public final class CostDashboardModel {
  public private(set) var isEnabled: Bool
  public private(set) var selectedPeriod: CostDisplayPeriod
  public private(set) var isRefreshing = false
  public private(set) var authoritativeRows: [AuthoritativeCostRow] = []
  public private(set) var estimateRows: [EstimatedCostRow] = []
  public private(set) var lastRefreshAt: Date?

  @ObservationIgnored private let authoritativeSources: [AuthoritativeCostSource]
  @ObservationIgnored private let estimateProviders: [ProviderID]
  @ObservationIgnored private let store: CostStore
  @ObservationIgnored private let authoritativeLoader:
    @Sendable (AuthoritativeCostSource) async -> Result<
      AuthoritativeCostSnapshot, ProviderFailure
    >
  @ObservationIgnored private let periodEstimateLoader:
    @Sendable (ProviderID) async -> Result<EstimatedCostPeriodCollection, ProviderFailure>
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var refreshToken: UUID?
  @ObservationIgnored private var agingTask: Task<Void, Never>?

  public init(
    enabled: Bool,
    selectedPeriod: CostDisplayPeriod = .week,
    authoritativeSources: [AuthoritativeCostSource],
    estimateProviders: [ProviderID],
    store: CostStore = CostStore(),
    authoritativeLoader:
      @escaping @Sendable (AuthoritativeCostSource) async -> Result<
        AuthoritativeCostSnapshot, ProviderFailure
      >,
    periodEstimateLoader:
      @escaping @Sendable (ProviderID) async -> Result<
        EstimatedCostPeriodCollection, ProviderFailure
      >,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.isEnabled = enabled
    self.selectedPeriod = selectedPeriod
    self.authoritativeSources = authoritativeSources
    self.estimateProviders = estimateProviders
    self.store = store
    self.authoritativeLoader = authoritativeLoader
    self.periodEstimateLoader = periodEstimateLoader
    self.now = now
  }

  /// Compatibility initializer for callers that still supply one 7-day
  /// snapshot. New production code should use `periodEstimateLoader` so one
  /// scan populates all three display periods.
  public convenience init(
    enabled: Bool,
    authoritativeSources: [AuthoritativeCostSource],
    estimateProviders: [ProviderID],
    store: CostStore = CostStore(),
    authoritativeLoader:
      @escaping @Sendable (AuthoritativeCostSource) async -> Result<
        AuthoritativeCostSnapshot, ProviderFailure
      >,
    estimateLoader:
      @escaping @Sendable (ProviderID) async -> Result<
        EstimatedCostSnapshot, ProviderFailure
      >,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.init(
      enabled: enabled,
      selectedPeriod: .week,
      authoritativeSources: authoritativeSources,
      estimateProviders: estimateProviders,
      store: store,
      authoritativeLoader: authoritativeLoader,
      periodEstimateLoader: { provider in
        await estimateLoader(provider).map { snapshot in
          EstimatedCostPeriodCollection(
            provider: provider,
            snapshots: Dictionary(
              uniqueKeysWithValues: CostDisplayPeriod.allCases.map { ($0, snapshot) }))
        }
      },
      now: now)
  }

  public var diagnosticMetadata: CostDiagnosticMetadata {
    let authoritative = authoritativeRows.map { row in
      CostDiagnosticSourceMetadata(
        provider: row.source.provider,
        kind: .authoritative,
        phase: row.state.phase,
        errorKind: row.state.error?.kind,
        updatedAt: row.state.snapshot?.fetchedAt,
        catalogVersion: nil)
    }
    let estimated = estimateRows.map { row in
      CostDiagnosticSourceMetadata(
        provider: row.provider,
        kind: .estimate,
        phase: row.state.phase,
        errorKind: row.state.error?.kind,
        updatedAt: row.state.snapshot?.scannedAt,
        catalogVersion: row.state.snapshot?.catalogVersion)
    }
    return CostDiagnosticMetadata(
      isRefreshing: isRefreshing,
      lastRefreshAt: lastRefreshAt,
      sources: authoritative + estimated)
  }

  public func loadIfNeeded() async {
    await refreshCosts(force: false)
  }

  public func refreshCosts(force: Bool) async {
    guard isEnabled else { return }
    if let refreshTask {
      await refreshTask.value
      return
    }

    let token = UUID()
    refreshToken = token
    let task = Task<Void, Never> { @MainActor [weak self] in
      await self?.performRefresh(force: force)
    }
    refreshTask = task
    await task.value
    if refreshToken == token {
      refreshTask = nil
      refreshToken = nil
      isRefreshing = false
    }
  }

  public func setEnabled(_ enabled: Bool) async {
    if enabled {
      isEnabled = true
    } else {
      await disable()
    }
  }

  public func setDisplayPeriod(_ period: CostDisplayPeriod) async {
    guard selectedPeriod != period else { return }
    selectedPeriod = period
    await updateRows()
  }

  public func disable() async {
    isEnabled = false
    refreshToken = nil
    refreshTask?.cancel()
    refreshTask = nil
    agingTask?.cancel()
    agingTask = nil
    isRefreshing = false
    authoritativeRows = []
    estimateRows = []
    lastRefreshAt = nil
    await store.clear()
  }

  private func performRefresh(force: Bool) async {
    var authoritativeToLoad: [AuthoritativeCostSource] = []
    for source in authoritativeSources {
      let state = await store.authoritativeState(for: source.accountID)
      if force || state.phase != .healthy {
        authoritativeToLoad.append(source)
      }
    }

    var estimatesToLoad: [ProviderID] = []
    for provider in estimateProviders {
      var hasUnhealthyPeriod = false
      for period in CostDisplayPeriod.allCases {
        let state = await store.estimatedState(for: provider, period: period)
        if state.phase != .healthy {
          hasUnhealthyPeriod = true
          break
        }
      }
      if force || hasUnhealthyPeriod {
        estimatesToLoad.append(provider)
      }
    }

    guard !authoritativeToLoad.isEmpty || !estimatesToLoad.isEmpty else {
      await updateRows()
      return
    }

    isRefreshing = true
    let authoritativeLoader = self.authoritativeLoader
    let periodEstimateLoader = self.periodEstimateLoader
    await withTaskGroup(of: CostLoadResult.self) { group in
      for source in authoritativeToLoad {
        await store.markAuthoritativeRefreshing(source.accountID)
        group.addTask {
          .authoritative(
            accountID: source.accountID,
            result: await authoritativeLoader(source))
        }
      }
      for provider in estimatesToLoad {
        for period in CostDisplayPeriod.allCases {
          await store.markEstimateRefreshing(provider, period: period)
        }
        group.addTask {
          .estimate(
            provider: provider,
            result: await periodEstimateLoader(provider))
        }
      }

      for await result in group {
        guard !Task.isCancelled else { continue }
        switch result {
        case .authoritative(let accountID, let value):
          await store.acceptAuthoritative(value, accountID: accountID)
        case .estimate(let provider, let value):
          switch value {
          case .success(let collection):
            for period in CostDisplayPeriod.allCases {
              if let snapshot = collection.snapshots[period] {
                await store.acceptEstimate(
                  .success(snapshot), provider: provider, period: period)
              } else {
                await store.acceptEstimate(
                  .failure(
                    ProviderFailure(
                      kind: .decoding,
                      message: "The local cost scan did not produce every display period.")),
                  provider: provider,
                  period: period)
              }
            }
          case .failure(let failure):
            for period in CostDisplayPeriod.allCases {
              await store.acceptEstimate(
                .failure(failure), provider: provider, period: period)
            }
          }
        }
        await updateRows()
      }
    }

    guard !Task.isCancelled else { return }
    lastRefreshAt = now()
    await updateRows()
  }

  private func updateRows() async {
    var authoritative: [AuthoritativeCostRow] = []
    for source in authoritativeSources {
      authoritative.append(
        AuthoritativeCostRow(
          source: source,
          state: await store.authoritativeState(for: source.accountID)))
    }
    var estimates: [EstimatedCostRow] = []
    for provider in estimateProviders {
      estimates.append(
        EstimatedCostRow(
          provider: provider,
          state: await store.estimatedState(for: provider, period: selectedPeriod)))
    }
    authoritativeRows = authoritative
    estimateRows = estimates
    scheduleAging()
  }

  private func scheduleAging() {
    agingTask?.cancel()
    agingTask = nil
    guard isEnabled else { return }

    let authoritativeDeadlines = authoritativeRows.compactMap { row -> Date? in
      guard row.state.phase == .healthy, let fetchedAt = row.state.snapshot?.fetchedAt else {
        return nil
      }
      return fetchedAt.addingTimeInterval(CostStore.authoritativeTTL)
    }
    let estimateDeadlines = estimateRows.compactMap { row -> Date? in
      guard row.state.phase == .healthy, let scannedAt = row.state.snapshot?.scannedAt else {
        return nil
      }
      return scannedAt.addingTimeInterval(CostStore.estimateTTL)
    }
    guard let deadline = (authoritativeDeadlines + estimateDeadlines).min() else { return }
    let delay = max(0, deadline.timeIntervalSince(now())) + 0.01
    agingTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard let self, self.isEnabled else { return }
      await self.updateRows()
    }
  }
}

private enum CostLoadResult: Sendable {
  case authoritative(
    accountID: UUID,
    result: Result<AuthoritativeCostSnapshot, ProviderFailure>)
  case estimate(
    provider: ProviderID,
    result: Result<EstimatedCostPeriodCollection, ProviderFailure>)
}
