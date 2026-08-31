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

public struct CodexCostRecordParser: LocalUsageRecordParser {
  public static let provider: ProviderID = .codex
  public static let transcriptDirectories = CodexRolloutParser.transcriptDirectories

  private var currentModel: String?
  private var previousTotal: CodexCostUsage?
  private var needsChildBaseline = false
  private var currentProcessingTier: CostProcessingTier?
  private let fallbackProcessingTier: CostProcessingTier

  public init() {
    fallbackProcessingTier = .standard
  }

  public init(fallbackProcessingTier: CostProcessingTier) {
    self.fallbackProcessingTier = fallbackProcessingTier
  }

  public mutating func consume(_ record: Data) -> NormalizedModelUsage? {
    guard let decoded = try? JSONDecoder().decode(CodexCostRecord.self, from: record) else {
      return nil
    }
    switch decoded.type {
    case "session_meta":
      currentModel = nil
      previousTotal = nil
      currentProcessingTier = nil
      needsChildBaseline =
        decoded.payload.threadSource == "subagent"
        || decoded.payload.source?.isSubagent == true
      return nil
    case "turn_context":
      if let model = decoded.payload.model, !model.isEmpty {
        currentModel = model
      }
      return nil
    case "event_msg":
      if decoded.payload.type == "thread_settings_applied" {
        if let serviceTier = decoded.payload.threadSettings?.serviceTier {
          switch serviceTier {
          case "fast", "priority": currentProcessingTier = .fast
          case "default", "standard": currentProcessingTier = .standard
          default: currentProcessingTier = nil
          }
        }
        return nil
      }
      guard decoded.payload.type == "token_count",
        let model = currentModel,
        let timestamp = LocalUsageTimestamp.parse(decoded.timestamp)
      else { return nil }
      if let total = decoded.payload.info?.totalTokenUsage {
        let previous = previousTotal
        previousTotal = total
        if needsChildBaseline {
          needsChildBaseline = false
          return nil
        }
        if total != previous, let usage = decoded.payload.info?.lastTokenUsage {
          return normalized(usage, model: model, timestamp: timestamp)
        }
        return consumeCumulative(
          total,
          previous: previous,
          model: model,
          timestamp: timestamp)
      }
      guard let usage = decoded.payload.info?.lastTokenUsage else { return nil }
      return normalized(usage, model: model, timestamp: timestamp)
    default:
      return nil
    }
  }

  public mutating func finish() {
    self = Self()
  }

  private mutating func consumeCumulative(
    _ total: CodexCostUsage,
    previous previousTotal: CodexCostUsage?,
    model: String,
    timestamp: Date
  ) -> NormalizedModelUsage? {
    guard let previousTotal else {
      return normalized(total, model: model, timestamp: timestamp)
    }
    guard total.isAtLeast(previousTotal) else {
      return nil
    }
    return normalized(total.subtracting(previousTotal), model: model, timestamp: timestamp)
  }

  private func normalized(
    _ usage: CodexCostUsage,
    model: String,
    timestamp: Date
  ) -> NormalizedModelUsage? {
    guard usage.hasTokens else { return nil }
    let cacheReadTokens = min(usage.cachedInputTokens, usage.inputTokens)
    let cacheWriteTokens = min(
      usage.cacheWriteInputTokens,
      usage.inputTokens - cacheReadTokens)
    return NormalizedModelUsage(
      provider: Self.provider,
      modelID: model,
      timestamp: timestamp,
      uncachedInputTokens: usage.inputTokens - cacheReadTokens - cacheWriteTokens,
      cacheReadTokens: cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens,
      outputTokens: usage.outputTokens,
      processingTier: currentProcessingTier ?? fallbackProcessingTier)
  }
}

public struct ClaudeCostRecordParser: LocalUsageRecordParser {
  public static let provider: ProviderID = .claude
  public static let transcriptDirectories = ClaudeTranscriptParser.transcriptDirectories

  private var seenMessageIDs: Set<String> = []

  public init() {}

  public mutating func consume(_ record: Data) -> NormalizedModelUsage? {
    guard let decoded = try? JSONDecoder().decode(ClaudeCostRecord.self, from: record),
      let message = decoded.message,
      let usage = message.usage,
      let model = message.model,
      !model.isEmpty,
      let timestamp = LocalUsageTimestamp.parse(decoded.timestamp)
    else { return nil }
    let messageID = message.id ?? ""
    if !messageID.isEmpty, !seenMessageIDs.insert(messageID).inserted {
      return nil
    }
    return NormalizedModelUsage(
      provider: Self.provider,
      modelID: model,
      timestamp: timestamp,
      uncachedInputTokens: usage.inputTokens,
      cacheReadTokens: usage.cacheReadInputTokens,
      cacheWriteTokens: usage.cacheCreationInputTokens,
      outputTokens: usage.outputTokens,
      deduplicationKey: messageID)
  }

  public mutating func finish() {
    seenMessageIDs.removeAll(keepingCapacity: false)
  }
}

public struct KimiCostRecordParser: LocalUsageRecordParser {
  public static let provider: ProviderID = .kimi
  public static let transcriptDirectories = KimiWireParser.transcriptDirectories

  public init() {}

  public mutating func consume(_ record: Data) -> NormalizedModelUsage? {
    guard let decoded = try? JSONDecoder().decode(KimiCostRecord.self, from: record),
      decoded.type == "usage.record",
      let usage = decoded.usage,
      let model = decoded.model,
      !model.isEmpty
    else { return nil }
    return NormalizedModelUsage(
      provider: Self.provider,
      modelID: model,
      timestamp: Date(timeIntervalSince1970: decoded.time / 1_000),
      uncachedInputTokens: usage.inputOther,
      cacheReadTokens: usage.inputCacheRead,
      cacheWriteTokens: usage.inputCacheCreation,
      outputTokens: usage.output)
  }

  public mutating func finish() {}
}

private struct CodexCostRecord: Decodable {
  let timestamp: String
  let type: String
  let payload: Payload

  struct Payload: Decodable {
    let type: String?
    let model: String?
    let info: Info?
    let source: Source?
    let threadSource: String?
    let threadSettings: ThreadSettings?

    enum CodingKeys: String, CodingKey {
      case type
      case model
      case info
      case source
      case threadSource = "thread_source"
      case threadSettings = "thread_settings"
    }
  }

  struct ThreadSettings: Decodable {
    let serviceTier: String?

    enum CodingKeys: String, CodingKey {
      case serviceTier = "service_tier"
    }
  }

  struct Info: Decodable {
    let lastTokenUsage: CodexCostUsage?
    let totalTokenUsage: CodexCostUsage?

    enum CodingKeys: String, CodingKey {
      case lastTokenUsage = "last_token_usage"
      case totalTokenUsage = "total_token_usage"
    }
  }

  struct Source: Decodable {
    let isSubagent: Bool

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let value = try? container.decode(String.self) {
        isSubagent = value == "subagent"
        return
      }
      let keyed = try decoder.container(keyedBy: DynamicCodingKey.self)
      isSubagent = keyed.contains(DynamicCodingKey("subagent"))
    }
  }
}

private struct CodexCostUsage: Decodable, Equatable {
  let inputTokens: Int
  let cachedInputTokens: Int
  let cacheWriteInputTokens: Int
  let outputTokens: Int

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case cachedInputTokens = "cached_input_tokens"
    case cacheWriteInputTokens = "cache_write_input_tokens"
    case outputTokens = "output_tokens"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    inputTokens = max(try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0, 0)
    cachedInputTokens = max(
      try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0,
      0)
    cacheWriteInputTokens = max(
      try container.decodeIfPresent(Int.self, forKey: .cacheWriteInputTokens) ?? 0,
      0)
    outputTokens = max(try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0, 0)
  }

  private init(
    inputTokens: Int,
    cachedInputTokens: Int,
    cacheWriteInputTokens: Int,
    outputTokens: Int
  ) {
    self.inputTokens = inputTokens
    self.cachedInputTokens = cachedInputTokens
    self.cacheWriteInputTokens = cacheWriteInputTokens
    self.outputTokens = outputTokens
  }

  var hasTokens: Bool {
    inputTokens > 0 || cachedInputTokens > 0 || cacheWriteInputTokens > 0
      || outputTokens > 0
  }

  func isAtLeast(_ other: Self) -> Bool {
    inputTokens >= other.inputTokens
      && cachedInputTokens >= other.cachedInputTokens
      && cacheWriteInputTokens >= other.cacheWriteInputTokens
      && outputTokens >= other.outputTokens
  }

  func subtracting(_ other: Self) -> Self {
    Self(
      inputTokens: inputTokens - other.inputTokens,
      cachedInputTokens: cachedInputTokens - other.cachedInputTokens,
      cacheWriteInputTokens: cacheWriteInputTokens - other.cacheWriteInputTokens,
      outputTokens: outputTokens - other.outputTokens)
  }
}

private struct ClaudeCostRecord: Decodable {
  let timestamp: String
  let message: Message?

  struct Message: Decodable {
    let id: String?
    let model: String?
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

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      inputTokens = max(try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0, 0)
      outputTokens = max(try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0, 0)
      cacheReadInputTokens = max(
        try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0,
        0)
      cacheCreationInputTokens = max(
        try container.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0,
        0)
    }
  }
}

private struct KimiCostRecord: Decodable {
  let type: String
  let time: Double
  let model: String?
  let usage: Usage?

  struct Usage: Decodable {
    let inputOther: Int
    let output: Int
    let inputCacheRead: Int
    let inputCacheCreation: Int
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
  }
}
