import Foundation
import TokenLinkCore

public enum CodexRateLimitParseError: Error, Equatable {
  case missingPrimaryWindow
}

public enum CodexRateLimitParser {
  public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    let envelope = try JSONDecoder().decode(CodexEnvelope.self, from: data)
    let window =
      envelope.result.rateLimitsByLimitID?["codex"]?.primary
      ?? envelope.result.rateLimits?.primary
    guard let window else {
      throw CodexRateLimitParseError.missingPrimaryWindow
    }
    return QuotaSnapshot(
      provider: .codex,
      planLabel: nil,
      windows: [
        QuotaWindow(
          id: "primary",
          label: "Primary",
          usedPercent: window.usedPercent,
          remainingPercent: 100 - window.usedPercent,
          remainingCount: nil,
          limitCount: nil,
          resetsAt: Date(timeIntervalSince1970: window.resetsAt))
      ],
      source: .localAppServer,
      fetchedAt: fetchedAt)
  }
}

private struct CodexEnvelope: Decodable {
  let result: CodexResult
}

private struct CodexResult: Decodable {
  let rateLimitsByLimitID: [String: CodexLimit]?
  let rateLimits: CodexLimit?

  enum CodingKeys: String, CodingKey {
    case rateLimitsByLimitID = "rateLimitsByLimitId"
    case rateLimits
  }
}

private struct CodexLimit: Decodable {
  let limitID: String?
  let primary: CodexWindow?

  enum CodingKeys: String, CodingKey {
    case limitID = "limitId"
    case primary
  }
}

private struct CodexWindow: Decodable {
  let usedPercent: Double
  let resetsAt: Double
}
