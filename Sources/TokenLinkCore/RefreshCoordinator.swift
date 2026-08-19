import Foundation

public protocol QuotaProvider: Sendable {
  var id: ProviderID { get }
  func fetch() async -> Result<QuotaSnapshot, ProviderFailure>
}

public actor ProviderStore {
  private var states: [ProviderID: ProviderState] = [:]
  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  public func accept(
    _ result: Result<QuotaSnapshot, ProviderFailure>,
    provider: ProviderID
  ) {
    switch result {
    case .success(let snapshot):
      states[provider] = .init(phase: .healthy, snapshot: snapshot)
    case .failure(let failure):
      let old = states[provider]?.snapshot
      let phase: ProviderPhase =
        old == nil
        ? (failure.kind == .missingCredential ? .missingCredential : .error)
        : .stale
      states[provider] = .init(phase: phase, snapshot: old, error: failure)
    }
  }

  public func markRefreshing(_ provider: ProviderID) {
    let old = states[provider]
    states[provider] = .init(
      phase: .refreshing,
      snapshot: old?.snapshot,
      error: nil)
  }

  public func state(
    for provider: ProviderID,
    refreshIntervalSeconds: TimeInterval = 300
  ) -> ProviderState {
    guard let state = states[provider] else {
      return .init(phase: .disabled)
    }
    return aged(state, refreshIntervalSeconds: refreshIntervalSeconds)
  }

  public func allStates(
    refreshIntervalSeconds: TimeInterval = 300
  ) -> [ProviderID: ProviderState] {
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
  private let providers: [any QuotaProvider]
  private let store: ProviderStore

  public init(providers: [any QuotaProvider], store: ProviderStore) {
    self.providers = providers
    self.store = store
  }

  public func refreshAll() async {
    await withTaskGroup(
      of: (ProviderID, Result<QuotaSnapshot, ProviderFailure>).self
    ) { group in
      for provider in providers {
        await store.markRefreshing(provider.id)
        group.addTask {
          (provider.id, await provider.fetch())
        }
      }
      for await (id, result) in group {
        await store.accept(result, provider: id)
      }
    }
  }
}
