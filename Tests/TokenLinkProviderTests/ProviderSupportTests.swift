import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct ThrowingCredentials: CredentialReader {
  func apiKey(forAccount account: String) async throws -> String? {
    throw ProviderFailure.configuration("Keychain denied access.")
  }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
}

private struct UnreachableHTTPClient: HTTPClient {
  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    Issue.record("HTTP must not be called after a credential failure")
    return HTTPResponse(data: Data(), statusCode: 500)
  }
}

@Test func endpointPolicyRejectsPlainHTTPAndUnknownHosts() throws {
  let policy = EndpointPolicy(allowedHosts: ["api.kimi.com"])
  #expect(throws: ProviderHostError.self) {
    try policy.validate(URL(string: "http://api.kimi.com/coding/v1/usages")!)
  }
  #expect(throws: ProviderHostError.self) {
    try policy.validate(URL(string: "https://example.com/coding/v1/usages")!)
  }
  #expect(
    try policy.validate(URL(string: "https://api.kimi.com/coding/v1/usages")!).host
      == "api.kimi.com")
}

@Test func providersPreserveCredentialConfigurationFailures() async {
  let http = UnreachableHTTPClient()
  let credentials = ThrowingCredentials()
  let providers: [any QuotaProvider] = [
    KimiProvider(http: http, credentials: credentials),
    MiniMaxProvider(region: .global, http: http, credentials: credentials),
    GLMProvider(region: .global, http: http, credentials: credentials),
  ]

  for provider in providers {
    guard case .failure(let failure) = await provider.fetch() else {
      Issue.record("Expected credential failure for \(provider.id.rawValue)")
      continue
    }
    #expect(failure.kind == .configuration)
  }
}

@Test func urlSessionClientRejectsRedirectsBeforeFollowingThem() throws {
  let original = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
  let redirected = URLRequest(url: URL(string: "https://example.com/steal")!)
  let response = try #require(
    HTTPURLResponse(
      url: original.url!,
      statusCode: 302,
      httpVersion: nil,
      headerFields: ["Location": redirected.url!.absoluteString]))
  let task = URLSession.shared.dataTask(with: original)
  let delegate = RedirectRejectingDelegate()
  var acceptedRequest: URLRequest? = redirected

  delegate.urlSession(
    URLSession.shared,
    task: task,
    willPerformHTTPRedirection: response,
    newRequest: redirected
  ) { acceptedRequest = $0 }

  #expect(acceptedRequest == nil)
}
