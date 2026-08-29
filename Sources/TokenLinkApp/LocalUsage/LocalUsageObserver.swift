import Foundation
import TokenLinkCore

/// Scans local CLI transcripts (read-only) and aggregates token usage per
/// provider. This is a beta feature: it exists to cross-check
/// provider-reported quota against locally observed consumption. It reads
/// only the three documented directories below, only files modified within
/// the window, and only token counters — never message content.
public struct LocalUsageObserver: @unchecked Sendable {
  /// Files larger than this are skipped (beta safeguard against huge logs).
  public static let maximumFileBytes = 52_428_800
  public static let maxFileBytes = maximumFileBytes

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
    (try? scan(parser, since: since).summary) ?? LocalUsageSummary(provider: P.provider)
  }

  /// Streams eligible files in stable path order and retains only aggregate
  /// counters. The report deliberately contains no file paths or raw records.
  public func scan<P: LocalUsageParsing>(
    _ parser: P.Type,
    since: Date
  ) throws -> LocalUsageScanReport {
    var files: [URL] = []
    for relative in P.transcriptDirectories {
      let directory = homeURL.appending(path: relative, directoryHint: .isDirectory)
      guard
        let enumerator = fileManager.enumerator(
          at: directory,
          includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
          options: [.skipsHiddenFiles])
      else { continue }
      for case let file as URL in enumerator where file.pathExtension == "jsonl" {
        files.append(file.standardizedFileURL)
      }
    }
    files.sort { $0.path < $1.path }

    var summary = LocalUsageSummary(provider: P.provider)
    var seenEventIDs: Set<String> = []
    var processedFileCount = 0
    var staleFileCount = 0
    var oversizedFileCount = 0
    var unreadableFileCount = 0
    var oversizedRecordCount = 0

    for file in files {
      try Task.checkCancellation()
      guard
        let values = try? file.resourceValues(
          forKeys: [.contentModificationDateKey, .fileSizeKey]),
        let modified = values.contentModificationDate,
        let size = values.fileSize
      else {
        unreadableFileCount += 1
        continue
      }
      guard modified >= since else {
        staleFileCount += 1
        continue
      }
      guard size <= Self.maximumFileBytes else {
        oversizedFileCount += 1
        continue
      }

      do {
        let readReport = try JSONLStreamingReader().read(url: file) { record in
          for event in P.parseEvents(from: record) where event.timestamp >= since {
            if !event.dedupeKey.isEmpty,
              !seenEventIDs.insert(event.dedupeKey).inserted
            {
              continue
            }
            summary.inputTokens += event.inputTokens
            summary.outputTokens += event.outputTokens
            summary.cachedInputTokens += event.cachedInputTokens
            summary.eventCount += 1
          }
        }
        processedFileCount += 1
        oversizedRecordCount += readReport.oversizedRecordCount
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        unreadableFileCount += 1
      }
    }

    return LocalUsageScanReport(
      summary: summary,
      processedFileCount: processedFileCount,
      staleFileCount: staleFileCount,
      oversizedFileCount: oversizedFileCount,
      unreadableFileCount: unreadableFileCount,
      oversizedRecordCount: oversizedRecordCount)
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

public struct LocalUsageScanReport: Equatable, Sendable {
  public let summary: LocalUsageSummary
  public let processedFileCount: Int
  public let staleFileCount: Int
  public let oversizedFileCount: Int
  public let unreadableFileCount: Int
  public let oversizedRecordCount: Int

  public init(
    summary: LocalUsageSummary,
    processedFileCount: Int,
    staleFileCount: Int,
    oversizedFileCount: Int,
    unreadableFileCount: Int,
    oversizedRecordCount: Int
  ) {
    self.summary = summary
    self.processedFileCount = processedFileCount
    self.staleFileCount = staleFileCount
    self.oversizedFileCount = oversizedFileCount
    self.unreadableFileCount = unreadableFileCount
    self.oversizedRecordCount = oversizedRecordCount
  }
}
