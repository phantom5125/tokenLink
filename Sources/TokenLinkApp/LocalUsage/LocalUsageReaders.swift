import Foundation
import TokenLinkCore

/// Shared ISO8601 parsing that tolerates fractional seconds.
enum LocalUsageTimestamp {
  static func parse(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
  }
}

/// Codex CLI rollout files: `~/.codex/sessions/**/*.jsonl`, `token_count`
/// events carry per-turn usage in `info.last_token_usage`.
public enum CodexRolloutParser: LocalUsageParsing {
  public static let provider: ProviderID = .codex
  public static let transcriptDirectories = [".codex/sessions"]

  public static func parseEvents(from data: Data) -> [TokenUsageEvent] {
    data.split(separator: 0x0A).compactMap { line in
      guard let record = try? JSONDecoder().decode(RolloutRecord.self, from: Data(line)),
        record.payload.type == "token_count",
        let usage = record.payload.info?.lastTokenUsage,
        let timestamp = LocalUsageTimestamp.parse(record.timestamp)
      else { return nil }
      return TokenUsageEvent(
        timestamp: timestamp,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cachedInputTokens: usage.cachedInputTokens)
    }
  }

  private struct RolloutRecord: Decodable {
    let timestamp: String
    let payload: Payload

    struct Payload: Decodable {
      let type: String
      let info: Info?
    }

    struct Info: Decodable {
      let lastTokenUsage: Usage?

      enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
      }
    }

    struct Usage: Decodable {
      let inputTokens: Int
      let cachedInputTokens: Int
      let outputTokens: Int

      enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
      }
    }
  }
}

/// Claude Code transcripts: `~/.claude/projects/**/*.jsonl`, assistant
/// messages carry `message.usage`. Deduplicated by message id.
public enum ClaudeTranscriptParser: LocalUsageParsing {
  public static let provider: ProviderID = .claude
  public static let transcriptDirectories = [".claude/projects"]

  public static func parseEvents(from data: Data) -> [TokenUsageEvent] {
    data.split(separator: 0x0A).compactMap { line in
      guard let record = try? JSONDecoder().decode(TranscriptRecord.self, from: Data(line)),
        let message = record.message, let usage = message.usage,
        let timestamp = LocalUsageTimestamp.parse(record.timestamp)
      else { return nil }
      return TokenUsageEvent(
        timestamp: timestamp,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cachedInputTokens: usage.cacheReadInputTokens + usage.cacheCreationInputTokens,
        dedupeKey: message.id ?? "")
    }
  }

  private struct TranscriptRecord: Decodable {
    let timestamp: String
    let message: Message?

    struct Message: Decodable {
      let id: String?
      let usage: Usage?
    }

    struct Usage: Decodable {
      let inputTokens: Int
      let outputTokens: Int
      let cacheReadInputTokens: Int
      let cacheCreationInputTokens: Int

      enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheReadInputTokens =
          try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        cacheCreationInputTokens =
          try container.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
      }
    }
  }
}

/// Kimi Code CLI wire logs: `~/.kimi-code/sessions/*/*/agents/*/wire.jsonl`,
/// `usage.record` events carry per-turn usage. Timestamps are epoch
/// milliseconds.
public enum KimiWireParser: LocalUsageParsing {
  public static let provider: ProviderID = .kimi
  public static let transcriptDirectories = [".kimi-code/sessions"]

  public static func parseEvents(from data: Data) -> [TokenUsageEvent] {
    data.split(separator: 0x0A).compactMap { line in
      guard let record = try? JSONDecoder().decode(WireRecord.self, from: Data(line)),
        record.type == "usage.record",
        let usage = record.usage
      else { return nil }
      return TokenUsageEvent(
        timestamp: Date(timeIntervalSince1970: record.time / 1_000),
        inputTokens: usage.inputOther + usage.inputCacheCreation,
        outputTokens: usage.output,
        cachedInputTokens: usage.inputCacheRead)
    }
  }

  private struct WireRecord: Decodable {
    let type: String
    let time: Double
    let usage: Usage?

    struct Usage: Decodable {
      let inputOther: Int
      let output: Int
      let inputCacheRead: Int
      let inputCacheCreation: Int
    }
  }
}
