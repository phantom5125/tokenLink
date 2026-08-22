import Foundation
import Testing
@testable import TokenLinkCore
@testable import TokenLinkProviders

@Test func parsesGLMWindowsWithoutInferringPlanLimits() throws {
    let snapshot = try GLMParser.parse(data: Fixture.load("glm-quota.json"),
                                       fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
    #expect(snapshot.provider == .glm)
    #expect(snapshot.windows.map(\.id) == ["5h", "weekly"])
    #expect(snapshot.windows.map(\.remainingPercent) == [93, 82])
    #expect(snapshot.windows.allSatisfy { $0.limitCount == nil })
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

@Test func glmProviderReportsMissingCredential() async {
    let http = StubHTTPClient(data: Data(), statusCode: 200)
    let provider = GLMProvider(region: .global, http: http,
                               credentials: StubCredentials(apiKey: nil))
    let result = await provider.fetch()
    switch result {
    case .success: Issue.record("expected failure")
    case .failure(let failure):
        #expect(failure.kind == .missingCredential)
    }
}

@Test func glmProviderMapsForbiddenToAuthentication() async {
    let http = StubHTTPClient(data: Data(), statusCode: 403)
    let provider = GLMProvider(region: .china, http: http,
                               credentials: StubCredentials(apiKey: "expired"))
    let result = await provider.fetch()
    switch result {
    case .success: Issue.record("expected failure")
    case .failure(let failure):
        #expect(failure.kind == .authentication)
    }
}

@Test func glmProviderParsesFixtureAcrossBothRegions() async throws {
    let http = StubHTTPClient(data: try Fixture.load("glm-quota.json"), statusCode: 200)
    let provider = GLMProvider(region: .global, http: http,
                               credentials: StubCredentials(apiKey: "key"))
    let result = await provider.fetch()
    let snapshot = try result.get()
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows.allSatisfy { $0.limitCount == nil })
}