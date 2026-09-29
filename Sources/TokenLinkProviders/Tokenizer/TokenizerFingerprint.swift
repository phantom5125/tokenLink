import Foundation
import TokenLinkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Published prompt-token observations are reference points, not proof of a
/// model's weights or lineage. The corpus and profiles are attributed in NOTICE.
public struct TokenizerFingerprintCatalog: Decodable, Sendable {
  public let version: Int
  public let source: String
  public let prompts: [String]
  public let profiles: [TokenizerReferenceProfile]

  public static func bundled() throws -> Self {
    guard let url = Bundle.module.url(forResource: "tokenizer-fingerprints", withExtension: "json")
    else { throw TokenizerFingerprintError.catalogUnavailable }
    let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard catalog.prompts.count == 30,
      !catalog.profiles.isEmpty,
      catalog.profiles.allSatisfy({ $0.counts.count == catalog.prompts.count })
    else { throw TokenizerFingerprintError.catalogUnavailable }
    return catalog
  }
}

public struct TokenizerReferenceProfile: Decodable, Sendable {
  public let model: String
  public let sampledAt: String
  public let counts: [Int]

  enum CodingKeys: String, CodingKey {
    case model
    case sampledAt = "sampled_at"
    case counts
  }
}

public enum TokenizerFingerprintError: Error, Equatable, Sendable {
  case catalogUnavailable
  case unsupportedProvider
  case invalidModel
  case httpStatus(Int)
  case responseTooLarge
  case invalidResponse
}

public struct TokenizerProbeTarget: Sendable {
  public let provider: ProviderID
  public let model: String
  public let endpoint: URL
  public let host: String
  public let usesAnthropicMessages: Bool

  public init(
    provider: ProviderID,
    model: String,
    miniMaxRegion: MiniMaxRegion = .global,
    glmRegion: GLMRegion = .global
  ) throws {
    let cleaned = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty, cleaned.utf8.count <= 128,
      !cleaned.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw TokenizerFingerprintError.invalidModel }
    self.provider = provider
    self.model = cleaned
    let url: URL
    switch provider {
    case .kimi:
      url = URL(string: "https://api.kimi.com/coding/v1/messages")!
      usesAnthropicMessages = true
    case .minimax:
      url = URL(
        string: miniMaxRegion == .china
          ? "https://api.minimaxi.com/anthropic/v1/messages"
          : "https://api.minimax.io/anthropic/v1/messages")!
      usesAnthropicMessages = true
    case .glm:
      url = URL(
        string: glmRegion == .china
          ? "https://open.bigmodel.cn/api/paas/v4/chat/completions"
          : "https://api.z.ai/api/paas/v4/chat/completions")!
      usesAnthropicMessages = false
    case .openrouter:
      url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
      usesAnthropicMessages = false
    case .deepseek:
      url = URL(string: "https://api.deepseek.com/chat/completions")!
      usesAnthropicMessages = false
    case .codex, .claude:
      throw TokenizerFingerprintError.unsupportedProvider
    }
    endpoint = url
    host = url.host!
  }
}

public struct TokenizerProbeClient: Sendable {
  private let http: any HTTPClient

  public init(http: any HTTPClient) {
    self.http = http
  }

  /// One user-initiated, bounded model call. A successful response without
  /// usage is missing evidence, never a zero-token observation.
  public func measure(
    target: TokenizerProbeTarget, apiKey: String, prompt: String
  ) async throws -> Int? {
    try Task.checkCancellation()
    var request = URLRequest(url: target.endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    if target.usesAnthropicMessages {
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": target.model,
      "max_tokens": 1,
      "messages": [["role": "user", "content": prompt]],
    ])
    let response = try await http.data(
      for: request, policy: EndpointPolicy(allowedHosts: [target.host]))
    guard (200..<300).contains(response.statusCode) else {
      throw TokenizerFingerprintError.httpStatus(response.statusCode)
    }
    guard response.data.count <= 1_048_576 else {
      throw TokenizerFingerprintError.responseTooLarge
    }
    let usage: UsageEnvelope
    do { usage = try JSONDecoder().decode(UsageEnvelope.self, from: response.data) } catch {
      throw TokenizerFingerprintError.invalidResponse
    }
    let count =
      target.usesAnthropicMessages
      ? usage.usage?.inputTokens : usage.usage?.promptTokens
    guard let count else { return nil }
    // A non-empty prompt cannot have zero native input tokens. Some gateways
    // report zero for cache hits instead of the underlying tokenizer count.
    if count == 0 { return nil }
    guard (1...10_000_000).contains(count) else {
      throw TokenizerFingerprintError.invalidResponse
    }
    return count
  }
}

private struct UsageEnvelope: Decodable {
  let usage: Usage?

  struct Usage: Decodable {
    let inputTokens: Int?
    let promptTokens: Int?

    enum CodingKeys: String, CodingKey {
      case inputTokens = "input_tokens"
      case promptTokens = "prompt_tokens"
    }
  }
}

public struct TokenizerFingerprintMatch: Sendable {
  public let model: String
  public let validSamples: Int
  public let modeOffset: Int?
  public let matchingSamples: Int
  public let score: Double?
  /// Reference count minus observed count for each probe.
  public let differences: [Int?]
}

public enum TokenizerFingerprintAnalysis {
  /// The exact-match share after removing the most common fixed count offset.
  /// At least 20 observations and 80% coverage are required before scoring.
  public static func compare(
    observed: [Int?], reference: TokenizerReferenceProfile
  ) -> TokenizerFingerprintMatch {
    let differences = zip(observed, reference.counts).map { count, expected in
      count.map { expected - $0 }
    }
    let valid = differences.compactMap { $0 }
    let frequencies = Dictionary(valid.map { ($0, 1) }, uniquingKeysWith: +)
    let best = frequencies.sorted {
      if $0.value != $1.value { return $0.value > $1.value }
      if abs($0.key) != abs($1.key) { return abs($0.key) < abs($1.key) }
      return $0.key < $1.key
    }.first
    let informative =
      valid.count >= 20
      && observed.count == reference.counts.count
      && Double(valid.count) / Double(reference.counts.count) >= 0.8
      && Set(observed.compactMap { $0 }).count >= 5
    return TokenizerFingerprintMatch(
      model: reference.model,
      validSamples: valid.count,
      modeOffset: informative ? best?.key : nil,
      matchingSamples: informative ? (best?.value ?? 0) : 0,
      score: informative ? Double(best?.value ?? 0) / Double(valid.count) : nil,
      differences: differences)
  }

  public static func rank(
    observed: [Int?], catalog: TokenizerFingerprintCatalog
  ) -> [TokenizerFingerprintMatch] {
    catalog.profiles.map { compare(observed: observed, reference: $0) }
      .sorted {
        if $0.score != $1.score { return ($0.score ?? -1) > ($1.score ?? -1) }
        return $0.model < $1.model
      }
  }
}
