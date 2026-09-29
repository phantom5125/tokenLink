import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private actor FingerprintHTTP: HTTPClient {
  let response: HTTPResponse
  private(set) var requests: [URLRequest] = []

  init(_ response: HTTPResponse) { self.response = response }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    _ = try policy.validate(request.url!)
    requests.append(request)
    return response
  }
}

@Test func bundledFingerprintCorpusAndProfilesAlign() throws {
  let catalog = try TokenizerFingerprintCatalog.bundled()
  #expect(catalog.prompts.count == 30)
  #expect(catalog.profiles.count >= 8)
  #expect(catalog.profiles.allSatisfy { $0.counts.count == 30 })
  #expect(catalog.prompts.contains { $0.contains("日本語") })
}

@Test func fingerprintComparisonRemovesConstantTemplateOffset() {
  let reference = TokenizerReferenceProfile(
    model: "reference", sampledAt: "2026-08-30", counts: Array(1...30))
  var observed: [Int?] = Array(1...30).map { $0 + 5 }
  observed[3] = 100
  observed[5] = nil
  let result = TokenizerFingerprintAnalysis.compare(observed: observed, reference: reference)
  #expect(result.validSamples == 29)
  #expect(result.modeOffset == -5)
  #expect(result.matchingSamples == 28)
  #expect(result.score == 28.0 / 29.0)
  #expect(result.differences[5] == nil)

  observed.replaceSubrange(0..<12, with: Array(repeating: nil, count: 12))
  let incomplete = TokenizerFingerprintAnalysis.compare(observed: observed, reference: reference)
  #expect(incomplete.score == nil)
}

@Test func fingerprintProbeSendsOnlyFixedPromptToAllowedHostAndReadsUsage() async throws {
  let http = FingerprintHTTP(
    HTTPResponse(
      data: Data(#"{"usage":{"prompt_tokens":17,"completion_tokens":1}}"#.utf8),
      statusCode: 200))
  let target = try TokenizerProbeTarget(provider: .openrouter, model: "qwen/qwen3.5-9b")
  let count = try await TokenizerProbeClient(http: http).measure(
    target: target, apiKey: "fixture-key", prompt: "fixed public text")
  #expect(count == 17)
  let request = try #require(await http.requests.first)
  #expect(request.url?.host == "openrouter.ai")
  #expect(request.httpMethod == "POST")
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
  let body = try #require(request.httpBody)
  let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect(object["max_tokens"] as? Int == 1)
  #expect(object["model"] as? String == "qwen/qwen3.5-9b")
}

@Test func missingUsageIsUninformativeAndBadStatusIsNotSilentlyScored() async throws {
  let target = try TokenizerProbeTarget(provider: .kimi, model: "k3-256k")
  let missing = TokenizerProbeClient(
    http: FingerprintHTTP(
      HTTPResponse(
        data: Data(#"{"usage":{}}"#.utf8), statusCode: 200)))
  #expect(try await missing.measure(target: target, apiKey: "fixture", prompt: "text") == nil)

  let rejected = TokenizerProbeClient(
    http: FingerprintHTTP(
      HTTPResponse(
        data: Data(), statusCode: 401)))
  await #expect(throws: TokenizerFingerprintError.httpStatus(401)) {
    try await rejected.measure(target: target, apiKey: "fixture", prompt: "text")
  }
}
