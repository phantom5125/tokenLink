import Foundation
import TokenLinkCore

/// Thin wrapper over `SpecDrivenProvider` for the default Kimi account.
public struct KimiProvider: QuotaProvider {
  public let id: ProviderID = .kimi
  private let inner: SpecDrivenProvider

  public init(
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.inner = SpecDrivenProvider(
      spec: ProviderRegistry.kimi,
      http: http,
      credentials: credentials,
      now: now)
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    await inner.fetch()
  }
}
