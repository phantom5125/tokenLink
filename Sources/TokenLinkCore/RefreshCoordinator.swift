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
    case .failure(let failure):
      let old = states[accountID]?.snapshot
      let phase: ProviderPhase =
        old == nil
        ? (failure.kind == .missingCredential ? .missingCredential : .error)
        : .stale
      states[accountID] = .init(phase: phase, snapshot: old, error: failure)
    }
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
