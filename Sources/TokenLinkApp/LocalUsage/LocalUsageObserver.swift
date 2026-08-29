import Foundation
import TokenLinkCore

/// Scans local CLI transcripts (read-only) and aggregates token usage per
/// provider. This is a beta feature: it exists to cross-check
/// provider-reported quota against locally observed consumption. It reads
/// only the three documented directories below, only files modified within
/// the window, and only token counters — never message content.
public struct LocalUsageObserver: @unchecked Sendable {
  /// Files larger than this are skipped (beta safeguard against huge logs).
  public static let maxFileBytes = 50 * 1_024 * 1_024

  private let homeURL: URL
  private let fileManager: FileManager

  public init(
    homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) {
    self.homeURL = homeURL
    self.fileManager = fileManager
  }

  /// Aggregates events from files modified since `since`.
  public func summarize<P: LocalUsageParsing>(
    _ parser: P.Type, since: Date
  ) -> LocalUsageSummary {
    var events: [TokenUsageEvent] = []
    for relative in P.transcriptDirectories {
      let directory = homeURL.appending(path: relative, directoryHint: .isDirectory)
      guard
        let enumerator = fileManager.enumerator(
          at: directory,
          includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
          options: [.skipsHiddenFiles])
      else { continue }
      for case let file as URL in enumerator where file.pathExtension == "jsonl" {
        guard
          let values = try? file.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]),
          let modified = values.contentModificationDate, modified >= since,
          let size = values.fileSize, size <= Self.maxFileBytes,
          let data = try? Data(contentsOf: file)
        else { continue }
        events.append(contentsOf: P.parseEvents(from: data))
      }
    }
    return LocalUsageAggregation.summarize(
      provider: P.provider, events: events, since: since)
  }

  /// All currently supported local sources, in provider order.
  public func summarizeAll(since: Date) -> [LocalUsageSummary] {
    [
      summarize(CodexRolloutParser.self, since: since),
      summarize(ClaudeTranscriptParser.self, since: since),
      summarize(KimiWireParser.self, since: since),
    ]
  }
}
