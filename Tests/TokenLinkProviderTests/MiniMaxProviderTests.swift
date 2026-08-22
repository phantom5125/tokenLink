import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct MiniMaxCredentials: CredentialReader {
  let key: String?
  func apiKey(forAccount account: String) async throws -> String? { key }
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
  let fetchedAt = Date(timeIntervalSince1970: 1_787_130_000)
  let snapshot = try MiniMaxParser.parse(
    data: Fixture.load("minimax-remains.json"),
    fetchedAt: fetchedAt)
  #expect(snapshot.provider == .minimax)
  #expect(snapshot.windows.map(\.remainingPercent) == [60, 92])
  #expect(snapshot.windows.map(\.id) == ["5h", "weekly"])
  #expect(snapshot.windows[0].resetsAt == fetchedAt.addingTimeInterval(7_200))
  #expect(snapshot.windows[1].resetsAt == fetchedAt.addingTimeInterval(172_800))
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
      == "https://www.minimaxi.com/v1/token_plan/remains")
  let policy = EndpointPolicy(allowedHosts: ["www.minimax.io", "www.minimaxi.com"])
  #expect(try policy.validate(MiniMaxRegion.global.endpoint).host == "www.minimax.io")
  #expect(try policy.validate(MiniMaxRegion.china.endpoint).host == "www.minimaxi.com")
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

@Test func minimaxProviderMapsForbiddenToAuthenticationFailure() async {
  let http = MiniMaxHTTPClient(response: HTTPResponse(data: Data(), statusCode: 403))
  let provider = MiniMaxProvider(
    region: .global,
    http: http,
    credentials: MiniMaxCredentials(key: "invalid"))

  guard case .failure(let failure) = await provider.fetch() else {
    Issue.record("Expected authentication failure")
    return
  }
  #expect(failure.kind == .authentication)
}

@Test func minimaxProviderMapsErrorEnvelopeToAuthenticationFailure() async {
  let envelope = Data(#"{"base_resp":{"status_code":2049,"status_msg":"invalid api key"}}"#.utf8)
  let http = MiniMaxHTTPClient(response: HTTPResponse(data: envelope, statusCode: 200))
  let provider = MiniMaxProvider(
    region: .global,
    http: http,
    credentials: MiniMaxCredentials(key: "invalid"))

  guard case .failure(let failure) = await provider.fetch() else {
    Issue.record("Expected authentication failure")
    return
  }
  #expect(failure.kind == .authentication)
  #expect(failure.message.contains("invalid api key"))
}

@Test func minimaxProviderSurfacesOtherServiceErrorsAsNetwork() async {
  let envelope = Data(#"{"base_resp":{"status_code":1002,"status_msg":"rate limit"}}"#.utf8)
  let http = MiniMaxHTTPClient(response: HTTPResponse(data: envelope, statusCode: 200))
  let provider = MiniMaxProvider(
    region: .global,
    http: http,
    credentials: MiniMaxCredentials(key: "valid"))

  guard case .failure(let failure) = await provider.fetch() else {
    Issue.record("Expected network failure")
    return
  }
  #expect(failure.kind == .network)
  #expect(failure.message.contains("rate limit"))
}
