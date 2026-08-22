import Foundation
import TokenLinkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
  public let data: Data
  public let statusCode: Int

  public init(data: Data, statusCode: Int) {
    self.data = data
    self.statusCode = statusCode
  }
}

public protocol HTTPClient: Sendable {
  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse
}

public protocol CredentialReader: Sendable {
  /// Reads the explicit (Keychain) API key stored under a credential account
  /// name. The default account of a provider uses `provider.rawValue`;
  /// additional accounts use "<provider>.<account-uuid>".
  func apiKey(forAccount account: String) async throws -> String?
  func cliAccessToken(for provider: ProviderID) async throws -> String?
  /// Reads an API key from the provider's allowlisted environment variables
  /// (see `ProviderSpec.credentialEnvVars`). Never scans arbitrary variables.
  func environmentAPIKey(for provider: ProviderID) async throws -> String?
}

extension CredentialReader {
  public func apiKey(for provider: ProviderID) async throws -> String? {
    try await apiKey(forAccount: provider.rawValue)
  }

  public func environmentAPIKey(for provider: ProviderID) async throws -> String? {
    nil
  }
}

public struct ProviderHostError: Error, Equatable, Sendable {
  public init() {}
}

public struct EndpointPolicy: Sendable {
  public let allowedHosts: Set<String>

  public init(allowedHosts: Set<String>) {
    self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
  }

  public init(allowedHosts: [String]) {
    self.init(allowedHosts: Set(allowedHosts))
  }

  public func validate(_ url: URL) throws -> URL {
    guard url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      let host = url.host?.lowercased(),
      allowedHosts.contains(host)
    else {
      throw ProviderHostError()
    }
    return url
  }
}

extension ProviderFailure {
  public static func authentication(_ message: String) -> Self {
    .init(kind: .authentication, message: message)
  }

  public static func decoding(_ message: String) -> Self {
    .init(kind: .decoding, message: message)
  }

  public static func process(_ message: String) -> Self {
    .init(kind: .process, message: message)
  }

  public static func timeout(_ message: String) -> Self {
    .init(kind: .timeout, message: message)
  }

  public static func configuration(_ message: String) -> Self {
    .init(kind: .configuration, message: message)
  }
}
