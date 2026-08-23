import Foundation
import TokenLinkCore

public enum CodexRateLimitParserError: Error, Equatable {
  case invalidJSON
  case missingPrimary
  case missingUsedPercent
  case invalidResetsAt
}

public enum CodexRateLimitParser {
  public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    let envelope = try JSONDecoder().decode(CodexRateLimitEnvelope.self, from: data)
    let primary = try primaryUsedPercent(from: envelope)
    let resetsAt = try primaryResetsAt(from: envelope)
    let window = QuotaWindow(
      id: "primary",
      label: "Primary",
      usedPercent: primary,
      remainingPercent: 100 - primary,
      remainingCount: nil,
      limitCount: nil,
      resetsAt: resetsAt)
    return QuotaSnapshot(
      provider: .codex,
      planLabel: nil,
      windows: [window],
      source: .localAppServer,
      fetchedAt: fetchedAt)
  }

  private static func primaryUsedPercent(from envelope: CodexRateLimitEnvelope) throws -> Double {
    if let direct = envelope.result?.rateLimitsByLimitId?["codex"]?.primary {
      if let value = direct.usedPercent { return value }
    }
    if let legacy = envelope.result?.rateLimits, legacy.limitId == "codex",
      let primary = legacy.primary, let value = primary.usedPercent
    {
      return value
    }
    throw CodexRateLimitParserError.missingUsedPercent
  }

  private static func primaryResetsAt(from envelope: CodexRateLimitEnvelope) throws -> Date? {
    let raw: Double?
    if let direct = envelope.result?.rateLimitsByLimitId?["codex"]?.primary {
      raw = direct.resetsAt
    } else if let legacy = envelope.result?.rateLimits,
      legacy.limitId == "codex",
      let primary = legacy.primary
    {
      raw = primary.resetsAt
    } else {
      return nil
    }
    guard let raw else { return nil }
    guard raw > 0 else { throw CodexRateLimitParserError.invalidResetsAt }
    return Date(timeIntervalSince1970: raw)
  }
}

private struct CodexRateLimitEnvelope: Decodable {
  let result: CodexRateLimitResult?

  struct CodexRateLimitResult: Decodable {
    let rateLimitsByLimitId: [String: CodexLimitEntry]?
    let rateLimits: CodexLegacyLimit?
  }

  struct CodexLimitEntry: Decodable {
    let primary: CodexPrimary?
  }

  struct CodexLegacyLimit: Decodable {
    let limitId: String?
    let primary: CodexPrimary?
  }

  struct CodexPrimary: Decodable {
    let usedPercent: Double?
    let resetsAt: Double?
  }
}
