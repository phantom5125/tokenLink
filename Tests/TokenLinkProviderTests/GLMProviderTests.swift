import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct GLMCredentials: CredentialReader {
  let key: String?
  func apiKey(forAccount account: String) async throws -> String? { key }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
}

private actor GLMHTTPClient: HTTPClient {
  let response: HTTPResponse
  private(set) var request: URLRequest?

  init(response: HTTPResponse) { self.response = response }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    _ = try policy.validate(try #require(request.url))
    self.request = request
    return response
  }
}

@Test func parsesGLMWindowsWithoutInferringPlanLimits() throws {
  let snapshot = try GLMParser.parse(
    data: Fixture.load("glm-quota.json"),
    fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
  #expect(snapshot.provider == .glm)
  #expect(snapshot.planLabel == "pro")
  #expect(snapshot.windows.map(\.id) == ["5h", "weekly", "mcp-monthly"])
  #expect(snapshot.windows.map(\.remainingPercent) == [93, 82, 97])
  #expect(snapshot.windows[0].remainingCount == 37_200_000)
  #expect(snapshot.windows[0].limitCount == 40_000_000)
  #expect(snapshot.windows[1].limitCount == nil)
  #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_787_137_200))
}

@Test func glmProviderUsesSelectedOfficialRegionAndRawAuthorizationKey() async throws {
  let http = GLMHTTPClient(
    response: HTTPResponse(
      data: try Fixture.load("glm-quota.json"), statusCode: 200))
  let provider = GLMProvider(
    region: .global,
    http: http,
    credentials: GLMCredentials(key: "glm-key"),
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  _ = try await provider.fetch().get()

  #expect(await http.request?.url == GLMRegion.global.endpoint)
  #expect(await http.request?.value(forHTTPHeaderField: "Authorization") == "glm-key")
}

@Test func glmRegionsAreRestrictedToOfficialHTTPSHosts() throws {
  let policy = EndpointPolicy(allowedHosts: ["api.z.ai", "open.bigmodel.cn"])
  #expect(try policy.validate(GLMRegion.global.endpoint).host == "api.z.ai")
  #expect(try policy.validate(GLMRegion.china.endpoint).host == "open.bigmodel.cn")
}
