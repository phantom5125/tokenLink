import Foundation

public protocol QuotaProvider: Sendable {
  var id: ProviderID { get }
  func fetch() async -> Result<QuotaSnapshot, ProviderFailure>
}

/// A provider instance bound to a concrete account. States are keyed by
/// account id so multiple accounts of the same provider can coexist.
public struct AccountProvider: Sendable {
  public let accountID: UUID
  public let provider: any QuotaProvider

  public init(accountID: UUID, provider: any QuotaProvider) {
    self.accountID = accountID
    self.provider = provider
  }
}

public actor ProviderStore {
  private var states: [UUID: ProviderState] = [:]
  /// Recent per-window samples for burn-rate projection, keyed by account and
  /// window id. Pruned to the estimator's max age on insert.
  private var samples: [UUID: [String: [BurnRateEstimator.Sample]]] = [:]
  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  public func accept(
    _ result: Result<QuotaSnapshot, ProviderFailure>,
    accountID: UUID
  ) {
    switch result {
    case .success(let snapshot):
      states[accountID] = .init(phase: .healthy, snapshot: snapshot)
      recordSamples(of: snapshot, accountID: accountID)
    case .failure(let failure):
      let old = states[accountID]?.snapshot
      let phase: ProviderPhase =
        old == nil
        ? (failure.kind == .missingCredential ? .missingCredential : .error)
        : .stale
      states[accountID] = .init(phase: phase, snapshot: old, error: failure)
    }
  }

  private func recordSamples(of snapshot: QuotaSnapshot, accountID: UUID) {
    var byWindow = samples[accountID] ?? [:]
    for window in snapshot.windows {
      var entries = byWindow[window.id] ?? []
      entries.append(.init(date: snapshot.fetchedAt, remaining: window.remainingPercent))
      entries.removeAll {
        snapshot.fetchedAt.timeIntervalSince($0.date) > BurnRateEstimator.maxSampleAge
      }
      byWindow[window.id] = entries
    }
    samples[accountID] = byWindow
  }

  /// Pace projection for the account's most constrained window; nil when the
  /// data is too thin or the window is not burning.
  public func burnEstimate(for accountID: UUID) -> BurnRateEstimate? {
    guard let snapshot = states[accountID]?.snapshot,
      let window = snapshot.mostConstrainedWindow
    else { return nil }
    return BurnRateEstimator.estimate(
      windowID: window.id,
      samples: samples[accountID]?[window.id] ?? [],
      now: now())
  }

  public func allBurnEstimates() -> [UUID: BurnRateEstimate] {
    var result: [UUID: BurnRateEstimate] = [:]
    for accountID in states.keys {
      if let estimate = burnEstimate(for: accountID) {
        result[accountID] = estimate
      }
    }
    return result
  }

  public func markRefreshing(_ accountID: UUID) {
    let old = states[accountID]
    states[accountID] = .init(
      phase: .refreshing,
      snapshot: old?.snapshot,
      error: nil)
  }

  public func state(
    for accountID: UUID,
    refreshIntervalSeconds: TimeInterval = 300
  ) -> ProviderState {
    guard let state = states[accountID] else {
      return .init(phase: .disabled)
    }
    return aged(state, refreshIntervalSeconds: refreshIntervalSeconds)
  }

  public func allStates(
    refreshIntervalSeconds: TimeInterval = 300
  ) -> [UUID: ProviderState] {
    states.mapValues {
      aged($0, refreshIntervalSeconds: refreshIntervalSeconds)
    }
  }

  private func aged(
    _ storedState: ProviderState,
    refreshIntervalSeconds: TimeInterval
  ) -> ProviderState {
    var state = storedState
    guard let snapshot = state.snapshot else { return state }
    let age = now().timeIntervalSince(snapshot.fetchedAt)
    if age > 86_400 {
      state.phase = .error
      state.error = .init(
        kind: .timeout,
        message: "Cached quota is older than 24 hours.")
    } else if state.phase == .healthy, age > refreshIntervalSeconds * 2 {
      state.phase = .stale
    }
    return state
  }
}

public struct RefreshCoordinator: Sendable {
  private let providers: [AccountProvider]
  private let store: ProviderStore

  public init(providers: [AccountProvider], store: ProviderStore) {
    self.providers = providers
    self.store = store
  }

  public func refreshAll() async {
    await withTaskGroup(
      of: (UUID, Result<QuotaSnapshot, ProviderFailure>).self
    ) { group in
      for entry in providers {
        await store.markRefreshing(entry.accountID)
        group.addTask {
          (entry.accountID, await entry.provider.fetch())
        }
      }
      for await (accountID, result) in group {
        await store.accept(result, accountID: accountID)
      }
    }
  }
}
