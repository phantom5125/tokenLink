import Foundation
import TokenLinkCore

public enum GLMRegion: String, Codable, Sendable {
  case global
  case china

  public var endpoint: URL {
    switch self {
    case .global:
      URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    case .china:
      URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    }
  }
}

/// Thin wrapper over `SpecDrivenProvider` for the default GLM account.
public struct GLMProvider: QuotaProvider {
  public let id: ProviderID = .glm
  private let inner: SpecDrivenProvider

  public init(
    region: GLMRegion,
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.inner = SpecDrivenProvider(
      spec: ProviderRegistry.glm,
      region: region.rawValue,
      http: http,
      credentials: credentials,
      now: now)
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    await inner.fetch()
  }
}
