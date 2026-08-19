import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct MiniMaxCredentials: CredentialReader {
  let key: String?
  func apiKey(for provider: ProviderID) async throws -> String? { key }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
}

private actor MiniMaxHTTPClient: HTTPClient {
  let response: HTTPResponse
  private(set) var request: URLRequest?

  init(response: HTTPResponse) { self.response = response }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    _ = try policy.validate(try #require(request.url))
    self.request = request
    return response
  }
}

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

@Test func minimaxRegionsUseOnlyOfficialHTTPSHosts() throws {
  #expect(
    MiniMaxRegion.global.endpoint.absoluteString == "https://www.minimax.io/v1/token_plan/remains")
  #expect(
    MiniMaxRegion.china.endpoint.absoluteString
      == "https://platform.minimaxi.com/v1/token_plan/remains")
  let policy = EndpointPolicy(allowedHosts: ["www.minimax.io", "platform.minimaxi.com"])
  #expect(try policy.validate(MiniMaxRegion.global.endpoint).host == "www.minimax.io")
  #expect(try policy.validate(MiniMaxRegion.china.endpoint).host == "platform.minimaxi.com")
}

@Test func minimaxProviderUsesSelectedRegionAndBearerKey() async throws {
  let http = MiniMaxHTTPClient(
    response: HTTPResponse(
      data: try Fixture.load("minimax-remains.json"), statusCode: 200))
  let provider = MiniMaxProvider(
    region: .china,
    http: http,
    credentials: MiniMaxCredentials(key: "minimax-key"),
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  _ = try await provider.fetch().get()

  #expect(await http.request?.url == MiniMaxRegion.china.endpoint)
  #expect(await http.request?.value(forHTTPHeaderField: "Authorization") == "Bearer minimax-key")
}
