import Foundation
import Testing
import TokenLinkCore
import TokenLinkProviders

@testable import TokenLinkApp

private actor FingerprintCredentials: CredentialReader {
  private(set) var reads = 0

  func apiKey(forAccount account: String) async throws -> String? {
    reads += 1
    return nil
  }

  func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
}

private actor UnusedFingerprintHTTP: HTTPClient {
  private(set) var calls = 0

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    calls += 1
    return HTTPResponse(data: Data(), statusCode: 500)
  }
}

@MainActor
@Test func fingerprintSessionDoesNotReadKeyOrCallNetworkUntilManualStart() async throws {
  let credentials = FingerprintCredentials()
  let http = UnusedFingerprintHTTP()
  let session = TokenizerFingerprintSession(
    credentials: credentials, client: TokenizerProbeClient(http: http))
  #expect(await credentials.reads == 0)
  #expect(await http.calls == 0)

  let target = try TokenizerProbeTarget(provider: .openrouter, model: "qwen/qwen3.5-9b")
  session.start(credentialAccount: "openrouter", target: target)
  for _ in 0..<100 {
    if !session.isRunning { break }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(!session.isRunning)
  #expect(session.failure == .missingKey)
  #expect(await credentials.reads == 1)
  #expect(await http.calls == 0)
}
