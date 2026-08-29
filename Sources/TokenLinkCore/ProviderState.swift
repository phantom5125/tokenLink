import Foundation

public enum ProviderErrorKind: String, Codable, Sendable {
  case missingCredential
  case authentication
  case network
  case decoding
  case process
  case timeout
  case configuration
}

public struct ProviderFailure: Error, Equatable, Sendable {
  public let kind: ProviderErrorKind
  public let message: String

  public init(kind: ProviderErrorKind, message: String) {
    self.kind = kind
    self.message = message
  }

  public static func network(_ message: String) -> Self {
    .init(kind: .network, message: message)
  }

  public static func missingCredential(_ message: String) -> Self {
    .init(kind: .missingCredential, message: message)
  }
}

extension ProviderFailure: LocalizedError {
  public var errorDescription: String? { message }
}

public enum ProviderPhase: String, Codable, Sendable {
  case disabled
  case missingCredential
  case refreshing
  case healthy
  case stale
  case error
}

public struct ProviderState: Equatable, Sendable {
  public var phase: ProviderPhase
  public var snapshot: QuotaSnapshot?
  public var error: ProviderFailure?

  public init(
    phase: ProviderPhase,
    snapshot: QuotaSnapshot? = nil,
    error: ProviderFailure? = nil
  ) {
    self.phase = phase
    self.snapshot = snapshot
    self.error = error
  }
}
