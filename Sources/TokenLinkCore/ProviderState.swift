import Foundation

public enum ProviderErrorKind: String, Codable, Sendable {
  case missingCredential, authentication, network, decoding, process, timeout, configuration
}

public struct ProviderFailure: Error, Equatable, Sendable {
  public let kind: ProviderErrorKind
  public let message: String

  public init(kind: ProviderErrorKind, message: String) {
    self.kind = kind
    self.message = message
  }

  public static func network(_ message: String) -> Self { .init(kind: .network, message: message) }
  public static func missingCredential(_ message: String) -> Self {
    .init(kind: .missingCredential, message: message)
  }
}

public enum ProviderPhase: String, Codable, Sendable {
  case disabled, missingCredential, refreshing, healthy, stale, error
}

public struct ProviderState: Equatable, Sendable {
  public var phase: ProviderPhase
  public var snapshot: QuotaSnapshot?
  public var error: ProviderFailure?

  public init(phase: ProviderPhase, snapshot: QuotaSnapshot? = nil, error: ProviderFailure? = nil) {
    self.phase = phase
    self.snapshot = snapshot
    self.error = error
  }
}

public protocol QuotaProvider: Sendable {
  var id: ProviderID { get }
  func fetch() async -> Result<QuotaSnapshot, ProviderFailure>
}

public actor ProviderStore {
  private var states: [ProviderID: ProviderState] = [:]
  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = Date.init) { self.now = now }

  public func accept(_ result: Result<QuotaSnapshot, ProviderFailure>, provider: ProviderID) {
    switch result {
    case .success(let snapshot):
      states[provider] = .init(phase: .healthy, snapshot: snapshot)
    case .failure(let failure):
      let old = states[provider]?.snapshot
      let phase: ProviderPhase =
        old == nil ? (failure.kind == .missingCredential ? .missingCredential : .error) : .stale
      states[provider] = .init(phase: phase, snapshot: old, error: failure)
    }
    _ = now()
  }

  public func markRefreshing(_ provider: ProviderID) {
    let old = states[provider]
    states[provider] = .init(phase: .refreshing, snapshot: old?.snapshot, error: nil)
  }

  public func state(
    for provider: ProviderID,
    refreshIntervalSeconds: TimeInterval = 300
  ) -> ProviderState {
    guard var state = states[provider] else { return .init(phase: .disabled) }
    guard state.phase == .healthy, let snapshot = state.snapshot else { return state }
    let age = now().timeIntervalSince(snapshot.fetchedAt)
    if age > 86_400 {
      state.phase = .error
      state.error = .init(kind: .timeout, message: "Cached quota is older than 24 hours.")
    } else if age > refreshIntervalSeconds * 2 {
      state.phase = .stale
    }
    return state
  }

  public func allStates() -> [ProviderID: ProviderState] { states }
}
