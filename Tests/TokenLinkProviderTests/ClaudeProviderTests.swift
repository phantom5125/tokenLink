import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct ClaudeCredentials: CredentialReader {
  let apiKeyValue: String?
  let cliTokenValue: String?
  let envValue: String?

  func apiKey(forAccount account: String) async throws -> String? { apiKeyValue }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { cliTokenValue }
  func environmentAPIKey(for provider: ProviderID) async throws -> String? { envValue }
}

private actor ClaudeHTTPClient: HTTPClient {
  let response: HTTPResponse
  private(set) var request: URLRequest?

  init(response: HTTPResponse) { self.response = response }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    _ = try policy.validate(try #require(request.url))
    self.request = request
    return response
  }
}

@Test func parsesClaudeFiveHourWeeklyAndExtraWindows() throws {
  let snapshot = try ClaudeParser.parse(
    data: Fixture.load("claude-usage.json"),
    fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
  #expect(snapshot.provider == .claude)
  #expect(snapshot.windows.map(\.id) == ["5h", "weekly", "seven_day_opus"])
  #expect(snapshot.windows.map(\.remainingPercent) == [46, 47, 87.5])
  #expect(snapshot.windows[0].resetsAt != nil)
  #expect(snapshot.windows[1].resetsAt != nil)  // fractional-seconds ISO8601
}

@Test func claudeParserRejectsResponsesWithoutUsableWindows() {
  let data = Data(#"{"error":"nope"}"#.utf8)
  #expect(throws: ClaudeParseError.self) {
    try ClaudeParser.parse(data: data, fetchedAt: .distantPast)
  }
}

@Test func claudeProviderSendsBetaHeaderAndPrefersCLICredential() async throws {
  let http = ClaudeHTTPClient(
    response: HTTPResponse(data: try Fixture.load("claude-usage.json"), statusCode: 200))
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.claude,
    http: http,
    credentials: ClaudeCredentials(
      apiKeyValue: nil, cliTokenValue: "cli-token", envValue: "env-token"))

  let result = await provider.fetch()

  guard case .success(let snapshot) = result else {
    Issue.record("Expected success, got \(result)")
    return
  }
  #expect(snapshot.source == .cliCredential)
  let request = await http.request
  #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer cli-token")
  #expect(request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
  #expect(request?.url?.host == "api.anthropic.com")
}

@Test func claudeProviderFallsBackToEnvironmentToken() async {
  let http = ClaudeHTTPClient(
    response: HTTPResponse(data: Data("{}".utf8), statusCode: 401))
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.claude,
    http: http,
    credentials: ClaudeCredentials(
      apiKeyValue: nil, cliTokenValue: nil, envValue: "env-token"))

  let result = await provider.fetch()

  guard case .failure(let failure) = result else {
    Issue.record("Expected authentication failure, got \(result)")
    return
  }
  #expect(failure.kind == .authentication)
  let request = await http.request
  #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer env-token")
}

@Test func claudeProviderReportsMissingCredential() async {
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.claude,
    http: ClaudeHTTPClient(response: HTTPResponse(data: Data(), statusCode: 200)),
    credentials: ClaudeCredentials(apiKeyValue: nil, cliTokenValue: nil, envValue: nil))

  let result = await provider.fetch()

  guard case .failure(let failure) = result else {
    Issue.record("Expected missing credential, got \(result)")
    return
  }
  #expect(failure.kind == .missingCredential)
}
