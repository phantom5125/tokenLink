import Foundation
import TokenLinkCore

/// Locally observed token usage for one provider over a time window. Used by
/// the beta "local usage" feature to cross-check provider-reported quota
/// against what the local CLI actually consumed. Numbers are estimates
/// aggregated from session transcripts; they never leave the Mac.
public struct LocalUsageSummary: Equatable, Sendable {
  public let provider: ProviderID
  public var inputTokens: Int
  public var outputTokens: Int
  public var cachedInputTokens: Int
  public var eventCount: Int

  public init(
    provider: ProviderID,
    inputTokens: Int = 0,
    outputTokens: Int = 0,
    cachedInputTokens: Int = 0,
    eventCount: Int = 0
  ) {
    self.provider = provider
    self.inputTokens = max(0, inputTokens)
    self.outputTokens = max(0, outputTokens)
    self.cachedInputTokens = max(0, cachedInputTokens)
    self.eventCount = max(0, eventCount)
  }

  public var totalTokens: Int {
    saturatingTokenAdd(inputTokens, outputTokens)
  }

  mutating func add(_ event: TokenUsageEvent) {
    inputTokens = saturatingTokenAdd(inputTokens, event.inputTokens)
    outputTokens = saturatingTokenAdd(outputTokens, event.outputTokens)
    cachedInputTokens = saturatingTokenAdd(cachedInputTokens, event.cachedInputTokens)
    eventCount = saturatingTokenAdd(eventCount, 1)
  }
}

/// A single timestamped token-usage observation parsed from a transcript.
public struct TokenUsageEvent: Equatable, Sendable {
  public let timestamp: Date
  public let inputTokens: Int
  public let outputTokens: Int
  public let cachedInputTokens: Int
  /// Deduplication key (e.g. Claude message id); empty when not applicable.
  public let dedupeKey: String

  public init(
    timestamp: Date, inputTokens: Int, outputTokens: Int,
    cachedInputTokens: Int = 0, dedupeKey: String = ""
  ) {
    self.timestamp = timestamp
    self.inputTokens = max(0, inputTokens)
    self.outputTokens = max(0, outputTokens)
    self.cachedInputTokens = max(0, cachedInputTokens)
    self.dedupeKey = dedupeKey
  }
}

/// Parses one provider's transcript format. Pure: data in, events out.
public protocol LocalUsageParsing: Sendable {
  static var provider: ProviderID { get }
  /// Relative path hints under the home directory, in priority order.
  static var transcriptDirectories: [String] { get }
  static func parseEvents(from data: Data) -> [TokenUsageEvent]
}

/// Stateful, per-file parser for model-aware API-equivalent cost estimation.
/// Implementations decode only metadata and token counters.
public protocol LocalUsageRecordParser: Sendable {
  static var provider: ProviderID { get }
  static var transcriptDirectories: [String] { get }

  init()
  mutating func consume(_ record: Data) -> NormalizedModelUsage?
  mutating func finish()
}

public enum LocalUsageAggregation {
  /// Sums events inside [since, now], deduplicating on non-empty keys.
  public static func summarize(
    provider: ProviderID,
    events: [TokenUsageEvent],
    since: Date
  ) -> LocalUsageSummary {
    var summary = LocalUsageSummary(provider: provider)
    var seen: Set<String> = []
    for event in events where event.timestamp >= since {
      if !event.dedupeKey.isEmpty && !seen.insert(event.dedupeKey).inserted {
        continue
      }
      summary.add(event)
    }
    return summary
  }
}

private func saturatingTokenAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
  return result.overflow ? Int.max : result.partialValue
}
