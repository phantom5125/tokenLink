import Foundation
import Testing

@testable import TokenLinkCore
@testable import TokenLinkProviders

@Test func parsesMiniMaxFiveHourAndWeeklyWindows() throws {
  let snapshot = try MiniMaxParser.parse(
    data: Fixture.load("minimax-remains.json"),
    fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
  #expect(snapshot.provider == .minimax)
  #expect(snapshot.windows.map(\.remainingPercent) == [60, 92])
  #expect(snapshot.windows.map(\.id) == ["5h", "weekly"])
}

@Test func rejectsMiniMaxErrorEnvelope() {
  let data = Data(#"{"base_resp":{"status_code":1004,"status_msg":"invalid key"}}"#.utf8)
  #expect(throws: MiniMaxParseError.self) {
    try MiniMaxParser.parse(data: data, fetchedAt: .distantPast)
  }
}

private struct StubHTTPClient: HTTPClient {
  let data: Data
  let statusCode: Int
  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    HTTPResponse(data: data, statusCode: statusCode)
  }
}

private struct StubCredentials: CredentialReader {
  let apiKey: String?
  func apiKey(for provider: ProviderID) async throws -> String? { apiKey }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
}

@Test func miniMaxProviderReportsMissingCredential() async {
  let http = StubHTTPClient(data: Data(), statusCode: 200)
  let provider = MiniMaxProvider(
    region: .global, http: http, credentials: StubCredentials(apiKey: nil))
  let result = await provider.fetch()
  switch result {
  case .success: Issue.record("expected failure")
  case .failure(let failure):
    #expect(failure.kind == .missingCredential)
  }
}

@Test func miniMaxProviderMapsAuthenticationFailure() async {
  let http = StubHTTPClient(data: Data(), statusCode: 401)
  let provider = MiniMaxProvider(
    region: .global, http: http, credentials: StubCredentials(apiKey: "expired"))
  let result = await provider.fetch()
  switch result {
  case .success: Issue.record("expected failure")
  case .failure(let failure):
    #expect(failure.kind == .authentication)
  }
}

@Test func miniMaxProviderParsesFixtureAcrossBothRegions() async throws {
  let http = StubHTTPClient(data: try Fixture.load("minimax-remains.json"), statusCode: 200)
  let provider = MiniMaxProvider(
    region: .china, http: http, credentials: StubCredentials(apiKey: "key"))
  let result = await provider.fetch()
  let snapshot = try result.get()
  #expect(snapshot.provider == .minimax)
  #expect(snapshot.windows.count == 2)
  #expect(snapshot.planLabel == "MiniMax-M2.5")
}
