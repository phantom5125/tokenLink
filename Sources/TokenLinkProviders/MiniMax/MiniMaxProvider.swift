import Foundation
import TokenLinkCore

public enum MiniMaxRegion: String, Codable, Sendable {
  case global
  case china

  public var endpoint: URL {
    switch self {
    case .global:
      URL(string: "https://www.minimax.io/v1/token_plan/remains")!
    case .china:
      URL(string: "https://www.minimaxi.com/v1/token_plan/remains")!
    }
  }
}

/// Thin wrapper over `SpecDrivenProvider` for the default MiniMax account.
public struct MiniMaxProvider: QuotaProvider {
  public let id: ProviderID = .minimax
  private let inner: SpecDrivenProvider

  public init(
    region: MiniMaxRegion,
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.inner = SpecDrivenProvider(
      spec: ProviderRegistry.minimax,
      region: region.rawValue,
      http: http,
      credentials: credentials,
      now: now)
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    await inner.fetch()
  }
}
