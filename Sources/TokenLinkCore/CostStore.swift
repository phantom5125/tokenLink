import Foundation

public struct AuthoritativeCostState: Equatable, Sendable {
  public var phase: ProviderPhase
  public var snapshot: AuthoritativeCostSnapshot?
  public var error: ProviderFailure?

  public init(
    phase: ProviderPhase,
    snapshot: AuthoritativeCostSnapshot? = nil,
    error: ProviderFailure? = nil
  ) {
    self.phase = phase
    self.snapshot = snapshot
    self.error = error
  }
}

public struct EstimatedCostState: Equatable, Sendable {
  public var phase: ProviderPhase
  public var snapshot: EstimatedCostSnapshot?
  public var error: ProviderFailure?

  public init(
    phase: ProviderPhase,
    snapshot: EstimatedCostSnapshot? = nil,
    error: ProviderFailure? = nil
  ) {
    self.phase = phase
    self.snapshot = snapshot
    self.error = error
  }
}

public actor CostStore {
  public static let authoritativeTTL: TimeInterval = 15 * 60
  public static let estimateTTL: TimeInterval = 30 * 60

  private var authoritativeStates: [UUID: AuthoritativeCostState] = [:]
  private var estimatedStates: [ProviderID: EstimatedCostState] = [:]
  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  public func acceptAuthoritative(
    _ result: Result<AuthoritativeCostSnapshot, ProviderFailure>,
    accountID: UUID
  ) {
    switch result {
    case .success(let snapshot):
      authoritativeStates[accountID] = .init(phase: .healthy, snapshot: snapshot)
    case .failure(let failure):
      let old = authoritativeStates[accountID]?.snapshot
      authoritativeStates[accountID] = .init(
        phase: failurePhase(for: failure, hasSnapshot: old != nil),
        snapshot: old,
        error: failure)
    }
  }

  public func acceptEstimate(
    _ result: Result<EstimatedCostSnapshot, ProviderFailure>,
    provider: ProviderID
  ) {
    switch result {
    case .success(let snapshot):
      estimatedStates[provider] = .init(phase: .healthy, snapshot: snapshot)
    case .failure(let failure):
      let old = estimatedStates[provider]?.snapshot
      estimatedStates[provider] = .init(
        phase: failurePhase(for: failure, hasSnapshot: old != nil),
        snapshot: old,
        error: failure)
    }
  }

  public func markAuthoritativeRefreshing(_ accountID: UUID) {
    let old = authoritativeStates[accountID]
    authoritativeStates[accountID] = .init(
      phase: .refreshing,
      snapshot: old?.snapshot)
  }

  public func markEstimateRefreshing(_ provider: ProviderID) {
    let old = estimatedStates[provider]
    estimatedStates[provider] = .init(
      phase: .refreshing,
      snapshot: old?.snapshot)
  }

  public func authoritativeState(for accountID: UUID) -> AuthoritativeCostState {
    guard let state = authoritativeStates[accountID] else {
      return .init(phase: .disabled)
    }
    return agedAuthoritative(state)
  }

  public func estimatedState(for provider: ProviderID) -> EstimatedCostState {
    guard let state = estimatedStates[provider] else {
      return .init(phase: .disabled)
    }
    return agedEstimate(state)
  }

  public func allAuthoritativeStates() -> [UUID: AuthoritativeCostState] {
    authoritativeStates.mapValues(agedAuthoritative)
  }

  public func allEstimatedStates() -> [ProviderID: EstimatedCostState] {
    estimatedStates.mapValues(agedEstimate)
  }

  public func clear() {
    authoritativeStates.removeAll()
    estimatedStates.removeAll()
  }

  private func failurePhase(
    for failure: ProviderFailure,
    hasSnapshot: Bool
  ) -> ProviderPhase {
    if hasSnapshot { return .stale }
    return failure.kind == .missingCredential ? .missingCredential : .error
  }

  private func agedAuthoritative(
    _ stored: AuthoritativeCostState
  ) -> AuthoritativeCostState {
    guard stored.phase == .healthy,
      let fetchedAt = stored.snapshot?.fetchedAt,
      now().timeIntervalSince(fetchedAt) > Self.authoritativeTTL
    else { return stored }
    var result = stored
    result.phase = .stale
    return result
  }

  private func agedEstimate(_ stored: EstimatedCostState) -> EstimatedCostState {
    guard stored.phase == .healthy,
      let scannedAt = stored.snapshot?.scannedAt,
      now().timeIntervalSince(scannedAt) > Self.estimateTTL
    else { return stored }
    var result = stored
    result.phase = .stale
    return result
  }
}
