import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct ChainCredentials: CredentialReader {
  var apiKeyValue: String?
  var cliTokenValue: String?
  var envValue: String?

  func apiKey(forAccount account: String) async throws -> String? { apiKeyValue }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { cliTokenValue }
  func environmentAPIKey(for provider: ProviderID) async throws -> String? { envValue }
}

private actor SpecHTTPClient: HTTPClient {
  let response: HTTPResponse
  private(set) var request: URLRequest?

  init(response: HTTPResponse) { self.response = response }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    _ = try policy.validate(try #require(request.url))
    self.request = request
    return response
  }
}

private func kimiFixtureClient() -> SpecHTTPClient {
  SpecHTTPClient(
    response: HTTPResponse(
      data: (try? Fixture.load("kimi-usages.json")) ?? Data(),
      statusCode: 200))
}

@Test func registryCoversEveryProviderWithSpecOrCustomMarker() {
  for id in ProviderRegistry.quotaProviderIDs {
    if id == .codex {
      #expect(ProviderRegistry.spec(for: id) == nil)
      #expect(ProviderRegistry.customProviders.contains(id))
    } else {
      #expect(ProviderRegistry.spec(for: id) != nil)
      #expect(!ProviderRegistry.customProviders.contains(id))
    }
  }
  for id in ProviderRegistry.authoritativeCostProviderIDs {
    #expect(ProviderRegistry.spec(for: id) == nil)
    #expect(!ProviderRegistry.customProviders.contains(id))
  }
}

@Test func registryDisplayNamesCoverCustomProviders() {
  for id in ProviderID.allCases {
    #expect(!ProviderRegistry.displayName(for: id).isEmpty)
  }
  #expect(ProviderRegistry.displayName(for: .codex) == "Codex")
}

@Test func registrySeparatesQuotaAndCostCapabilities() {
  #expect(
    ProviderRegistry.capabilities(for: .codex)
      == [.quota, .localCostEstimate])
  #expect(
    ProviderRegistry.capabilities(for: .openrouter)
      == [.authoritativeCost])
  #expect(
    ProviderRegistry.capabilities(for: .deepseek)
      == [.authoritativeCost])
  #expect(!ProviderRegistry.quotaProviderIDs.contains(.openrouter))
  #expect(ProviderRegistry.authoritativeCostProviderIDs == [.openrouter, .deepseek])
  #expect(ProviderRegistry.localCostEstimateProviderIDs == [.codex, .kimi, .claude])
}

@Test func specDrivenProviderSendsBearerHeader() async throws {
  let http = kimiFixtureClient()
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.kimi,
    http: http,
    credentials: ChainCredentials(apiKeyValue: "kimi-key"),
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  _ = try await provider.fetch().get()

  #expect(await http.request?.value(forHTTPHeaderField: "Authorization") == "Bearer kimi-key")
}

@Test func specDrivenProviderSendsRawAuthorizationHeader() async throws {
  let http = SpecHTTPClient(
    response: HTTPResponse(
      data: try Fixture.load("glm-quota.json"),
      statusCode: 200))
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.glm,
    region: GLMRegion.china.rawValue,
    http: http,
    credentials: ChainCredentials(apiKeyValue: "glm-key"),
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  _ = try await provider.fetch().get()

  #expect(await http.request?.value(forHTTPHeaderField: "Authorization") == "glm-key")
  #expect(await http.request?.url == GLMRegion.china.endpoint)
}

@Test func credentialChainPrefersKeychainOverCLIOverEnvironment() async throws {
  let http = kimiFixtureClient()
  let now: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_787_130_000) }

  let keychainFirst = SpecDrivenProvider(
    spec: ProviderRegistry.kimi, http: http,
    credentials: ChainCredentials(
      apiKeyValue: "explicit", cliTokenValue: "cli", envValue: "env"),
    now: now)
  #expect(try await keychainFirst.fetch().get().source == .apiKey)

  let cliSecond = SpecDrivenProvider(
    spec: ProviderRegistry.kimi, http: http,
    credentials: ChainCredentials(cliTokenValue: "cli", envValue: "env"),
    now: now)
  #expect(try await cliSecond.fetch().get().source == .cliCredential)

  let envLast = SpecDrivenProvider(
    spec: ProviderRegistry.kimi, http: http,
    credentials: ChainCredentials(envValue: "env"),
    now: now)
  #expect(try await envLast.fetch().get().source == .environmentVariable)
}

@Test func credentialChainSkipsCLIForProvidersWithoutCLISupport() async throws {
  let http = SpecHTTPClient(
    response: HTTPResponse(
      data: try Fixture.load("minimax-remains.json"),
      statusCode: 200))
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.minimax,
    http: http,
    credentials: ChainCredentials(cliTokenValue: "cli", envValue: "env"),
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  #expect(try await provider.fetch().get().source == .environmentVariable)
}

@Test func credentialChainReportsMissingCredentialWhenEmpty() async {
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.glm,
    http: kimiFixtureClient(),
    credentials: ChainCredentials())

  guard case .failure(let failure) = await provider.fetch() else {
    Issue.record("Expected missing credential failure")
    return
  }
  #expect(failure.kind == .missingCredential)
  #expect(failure.message == ProviderRegistry.glm.missingCredentialMessage)
}

@Test func specDrivenProviderReadsTheGivenCredentialAccount() async throws {
  final class AccountRecorder: CredentialReader, @unchecked Sendable {
    private(set) var account: String?
    func apiKey(forAccount account: String) async throws -> String? {
      self.account = account
      return nil
    }
    func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
  }
  let credentials = AccountRecorder()
  let secondary = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
  let provider = SpecDrivenProvider(
    spec: ProviderRegistry.minimax,
    credentialAccount: "minimax.\(secondary.uuidString)",
    http: kimiFixtureClient(),
    credentials: credentials)

  _ = await provider.fetch()

  #expect(credentials.account == "minimax.\(secondary.uuidString)")
}
