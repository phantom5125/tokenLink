import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct CostCredentials: CredentialReader {
  let value: String?

  func apiKey(forAccount account: String) async throws -> String? { value }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { nil }
}

private actor CostHTTPClient: HTTPClient {
  private let responses: [String: HTTPResponse]
  private(set) var requests: [URLRequest] = []

  init(responses: [String: HTTPResponse]) {
    self.responses = responses
  }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    guard let url = request.url else { throw ProviderHostError() }
    _ = try policy.validate(url)
    requests.append(request)
    return responses[url.path] ?? HTTPResponse(data: Data(), statusCode: 500)
  }
}

private func response(_ fixture: String, statusCode: Int = 200) throws -> HTTPResponse {
  HTTPResponse(data: try Fixture.load(fixture), statusCode: statusCode)
}

@Test func openRouterCombinesCreditsAndCurrentKeySpend() async throws {
  // Catches dropping one successful official endpoint or deriving the wrong remaining balance.
  let http = CostHTTPClient(
    responses: [
      "/api/v1/credits": try response("openrouter-credits.json"),
      "/api/v1/key": try response("openrouter-key.json"),
    ])
  let provider = OpenRouterCostProvider(
    credentialAccount: "openrouter.account",
    http: http,
    credentials: CostCredentials(value: "management-key"),
    now: { Date(timeIntervalSince1970: 1_788_048_000) })

  let snapshot = try await provider.fetch().get()

  #expect(
    snapshot.balances == [
      AccountBalance(
        currency: "USD", available: Decimal(string: "74.5")!, purchased: 100,
        used: Decimal(string: "25.5")!)
    ])
  #expect(
    snapshot.periodSpend.first { $0.period == .weekly }?.amount
      == CurrencyAmount(value: Decimal(string: "7.25")!, currency: "USD"))
  #expect(snapshot.warnings.isEmpty)
  #expect(snapshot.fetchedAt == Date(timeIntervalSince1970: 1_788_048_000))
  let requests = await http.requests
  #expect(requests.count == 2)
  #expect(
    requests.allSatisfy {
      $0.value(forHTTPHeaderField: "Authorization") == "Bearer management-key"
    })
  #expect(requests.allSatisfy { $0.url?.host == "openrouter.ai" })
}

@Test func openRouterKeepsCurrentKeyWhenCreditsRequireManagementPermission() async throws {
  // Catches treating a normal API key's partial `/key` data as wholly unavailable.
  let http = CostHTTPClient(
    responses: [
      "/api/v1/credits": HTTPResponse(data: Data(), statusCode: 403),
      "/api/v1/key": try response("openrouter-key.json"),
    ])
  let provider = OpenRouterCostProvider(
    http: http,
    credentials: CostCredentials(value: "api-key"))

  let snapshot = try await provider.fetch().get()

  #expect(snapshot.balances.first?.available.value == Decimal(string: "74.5"))
  #expect(snapshot.warnings == [.partialSource("credits")])
}

@Test func openRouterKeepsCreditsWhenCurrentKeyFails() async throws {
  // Catches one endpoint failure erasing authoritative lifetime credit data.
  let http = CostHTTPClient(
    responses: [
      "/api/v1/credits": try response("openrouter-credits.json"),
      "/api/v1/key": HTTPResponse(data: Data(), statusCode: 500),
    ])
  let provider = OpenRouterCostProvider(
    http: http,
    credentials: CostCredentials(value: "management-key"))

  let snapshot = try await provider.fetch().get()

  #expect(snapshot.balances.first?.available.value == Decimal(string: "74.5"))
  #expect(snapshot.periodSpend.isEmpty)
  #expect(snapshot.warnings == [.partialSource("key")])
}

@Test func openRouterFailsAuthenticationWhenNeitherEndpointIsUsable() async {
  // Catches masking a rejected credential as a generic network failure.
  let http = CostHTTPClient(
    responses: [
      "/api/v1/credits": HTTPResponse(data: Data(), statusCode: 403),
      "/api/v1/key": HTTPResponse(data: Data(), statusCode: 401),
    ])
  let provider = OpenRouterCostProvider(
    http: http,
    credentials: CostCredentials(value: "rejected"))

  guard case .failure(let failure) = await provider.fetch() else {
    Issue.record("Expected authentication failure")
    return
  }
  #expect(failure.kind == .authentication)
}

@Test func openRouterClampsExhaustedCreditsAndRequiresAllFailuresForAuthentication() async throws {
  // Catches negative remaining credit and over-reporting authentication for a mixed failure.
  let exhausted = CostHTTPClient(
    responses: [
      "/api/v1/credits": HTTPResponse(
        data: Data(#"{"data":{"total_credits":"1","total_usage":2}}"#.utf8),
        statusCode: 200),
      "/api/v1/key": HTTPResponse(data: Data(), statusCode: 500),
    ])
  let exhaustedProvider = OpenRouterCostProvider(
    http: exhausted,
    credentials: CostCredentials(value: "management-key"))
  let snapshot = try await exhaustedProvider.fetch().get()
  #expect(snapshot.balances.first?.available.value == 0)

  let mixedFailure = OpenRouterCostProvider(
    http: CostHTTPClient(
      responses: [
        "/api/v1/credits": HTTPResponse(data: Data(), statusCode: 403),
        "/api/v1/key": HTTPResponse(data: Data(), statusCode: 500),
      ]),
    credentials: CostCredentials(value: "management-key"))
  guard case .failure(let failure) = await mixedFailure.fetch() else {
    Issue.record("Expected a mixed endpoint failure")
    return
  }
  #expect(failure.kind == .network)
}

@Test func openRouterRejectsBooleanAndNonFiniteNumericValues() async {
  // Catches JSON booleans or non-finite strings being accepted as money.
  let malformedCredits = Data(
    #"{"data":{"total_credits":true,"total_usage":"NaN"}}"#.utf8)
  let http = CostHTTPClient(
    responses: [
      "/api/v1/credits": HTTPResponse(data: malformedCredits, statusCode: 200),
      "/api/v1/key": HTTPResponse(data: Data(#"{"data":{}}"#.utf8), statusCode: 200),
    ])
  let provider = OpenRouterCostProvider(
    http: http,
    credentials: CostCredentials(value: "management-key"))

  guard case .failure(let failure) = await provider.fetch() else {
    Issue.record("Expected decoding failure")
    return
  }
  #expect(failure.kind == .decoding)
}

@Test func deepSeekPreservesCurrenciesAvailabilityAndZero() async throws {
  // Catches currency conversion, zero-as-missing, or discarded availability state.
  let http = CostHTTPClient(
    responses: [
      "/user/balance": try response("deepseek-balance.json")
    ])
  let provider = DeepSeekCostProvider(
    credentialAccount: "deepseek.account",
    http: http,
    credentials: CostCredentials(value: "deepseek-key"),
    now: { Date(timeIntervalSince1970: 1_788_048_000) })

  let snapshot = try await provider.fetch().get()

  #expect(snapshot.isAvailable == false)
  #expect(snapshot.balances.map(\.available.currency) == ["CNY", "USD"])
  #expect(snapshot.balances.map(\.available.value) == [Decimal(string: "110.00")!, 0])
  #expect(snapshot.periodSpend.isEmpty)
  let request = try #require(await http.requests.first)
  #expect(request.url == URL(string: "https://api.deepseek.com/user/balance"))
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-key")
}

@Test func deepSeekMapsAuthenticationAndMalformedMoney() async {
  // Catches presenting rejected or malformed responses as a valid zero balance.
  let unauthorized = DeepSeekCostProvider(
    http: CostHTTPClient(
      responses: ["/user/balance": HTTPResponse(data: Data(), statusCode: 401)]),
    credentials: CostCredentials(value: "rejected"))
  guard case .failure(let authFailure) = await unauthorized.fetch() else {
    Issue.record("Expected authentication failure")
    return
  }
  #expect(authFailure.kind == .authentication)

  let malformed = DeepSeekCostProvider(
    http: CostHTTPClient(
      responses: [
        "/user/balance": HTTPResponse(
          data: Data(
            #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"Infinity","granted_balance":"0","topped_up_balance":"0"}]}"#
              .utf8),
          statusCode: 200)
      ]),
    credentials: CostCredentials(value: "deepseek-key"))
  guard case .failure(let decodingFailure) = await malformed.fetch() else {
    Issue.record("Expected decoding failure")
    return
  }
  #expect(decodingFailure.kind == .decoding)
}

@Test func authoritativeCostProvidersReportMissingCredentialsWithoutHTTP() async {
  // Catches a credential-less cost refresh making an external request.
  let http = CostHTTPClient(responses: [:])
  let providers: [any AuthoritativeCostProvider] = [
    OpenRouterCostProvider(http: http, credentials: CostCredentials(value: nil)),
    DeepSeekCostProvider(http: http, credentials: CostCredentials(value: nil)),
  ]

  for provider in providers {
    guard case .failure(let failure) = await provider.fetch() else {
      Issue.record("Expected missing credential for \(provider.id.rawValue)")
      continue
    }
    #expect(failure.kind == .missingCredential)
  }
  #expect(await http.requests.isEmpty)
}
