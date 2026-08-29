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
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cachedInputTokens = cachedInputTokens
    self.eventCount = eventCount
  }

  public var totalTokens: Int { inputTokens + outputTokens }
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
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cachedInputTokens = cachedInputTokens
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
      summary.inputTokens += event.inputTokens
      summary.outputTokens += event.outputTokens
      summary.cachedInputTokens += event.cachedInputTokens
      summary.eventCount += 1
    }
    return summary
  }
}
