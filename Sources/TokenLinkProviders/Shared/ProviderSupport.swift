import Foundation
import TokenLinkCore

public struct HTTPResponse: Sendable {
  public let data: Data
  public let statusCode: Int
}

public protocol HTTPClient: Sendable {
  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse
}

public protocol CredentialReader: Sendable {
  func apiKey(for provider: ProviderID) async throws -> String?
  func cliAccessToken(for provider: ProviderID) async throws -> String?
}

public struct ProviderHostError: Error, Equatable {}

public struct EndpointPolicy: Sendable {
  public let allowedHosts: Set<String>
  public init(allowedHosts: Set<String>) { self.allowedHosts = allowedHosts }
  public init(allowedHosts: [String]) { self.allowedHosts = Set(allowedHosts) }

  public func validate(_ url: URL) throws -> URL {
    guard url.scheme == "https", url.user == nil, url.password == nil,
      let host = url.host?.lowercased(), allowedHosts.contains(host)
    else { throw ProviderHostError() }
    return url
  }
}
