import Darwin
import Foundation
import Testing

@testable import TokenLinkApp

@Test func streamingReaderPreservesRecordsAcrossChunkBoundariesAndEOF() throws {
  // Catches truncating records at a 64 KiB chunk edge or dropping the final record.
  let first = Data(repeating: 0x41, count: 65_535)
  let second = Data(repeating: 0x42, count: 65_537)
  let final = Data("final-without-newline".utf8)
  var source = Data()
  source.append(first)
  source.append(0x0A)
  source.append(second)
  source.append(0x0A)
  source.append(final)
  let url = try temporaryFile(contents: source)
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

  var records: [Data] = []
  let report = try JSONLStreamingReader().read(url: url) { records.append($0) }

  #expect(JSONLStreamingReader.chunkBytes == 65_536)
  #expect(records == [first, second, final])
  #expect(report.deliveredRecordCount == 3)
  #expect(report.oversizedRecordCount == 0)
  #expect(report.bytesRead == source.count)
}

@Test func streamingReaderDeliversOneMiBAndSkipsOneByteOver() throws {
  // Catches an inclusive/exclusive limit bug or retaining the tail of an oversized record.
  let exact = Data(repeating: 0x58, count: 1_048_576)
  let oversized = Data(repeating: 0x59, count: 1_048_577)
  let final = Data("ok".utf8)
  var source = Data()
  source.append(exact)
  source.append(0x0A)
  source.append(oversized)
  source.append(0x0A)
  source.append(final)
  let url = try temporaryFile(contents: source)
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

  var deliveredSizes: [Int] = []
  let report = try JSONLStreamingReader().read(url: url) {
    deliveredSizes.append($0.count)
  }

  #expect(JSONLStreamingReader.maximumRecordBytes == 1_048_576)
  #expect(deliveredSizes == [1_048_576, 2])
  #expect(report.deliveredRecordCount == 2)
  #expect(report.oversizedRecordCount == 1)
}

@Test func streamingReaderHonorsCancellationBeforeReading() async throws {
  // Catches a cancelled local scan continuing to allocate and parse transcript data.
  let url = try temporaryFile(contents: Data("{}\n".utf8))
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

  let task = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    return try JSONLStreamingReader().read(url: url) { _ in }
  }

  do {
    _ = try await task.value
    Issue.record("Expected cancellation")
  } catch is CancellationError {
    // Expected.
  } catch {
    Issue.record("Expected CancellationError, got \(type(of: error))")
  }
}

@Test func streamingReaderEnforcesByteCeilingWhileFileIsOpen() throws {
  // Catches a file growing beyond the observer's preflight size check.
  let url = try temporaryFile(contents: Data("a\nb\nc\n".utf8))
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

  var records: [String] = []
  let truncated = try JSONLStreamingReader().read(url: url, maximumBytes: 4) {
    records.append(String(decoding: $0, as: UTF8.self))
  }

  #expect(truncated.bytesRead == 4)
  #expect(truncated.byteLimitExceeded)
  #expect(records == ["a", "b"])

  let exactURL = try temporaryFile(contents: Data("a\nb\n".utf8))
  defer { try? FileManager.default.removeItem(at: exactURL.deletingLastPathComponent()) }
  let exact = try JSONLStreamingReader().read(url: exactURL, maximumBytes: 4) { _ in }
  #expect(exact.bytesRead == 4)
  #expect(!exact.byteLimitExceeded)
}

@Test func streamingReaderEnforcesByteCeilingWhenFileGrowsAfterOpening() throws {
  // Catches a writer extending the transcript after the reader passed its preflight check.
  let url = try temporaryFile(contents: Data("a\n".utf8))
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let writer = try FileHandle(forWritingTo: url)
  defer { try? writer.close() }
  try writer.seekToEnd()

  var records: [String] = []
  let report = try JSONLStreamingReader().read(url: url, maximumBytes: 4) {
    let record = String(decoding: $0, as: UTF8.self)
    records.append(record)
    if record == "a" {
      try? writer.write(contentsOf: Data("b\nc\n".utf8))
    }
  }

  #expect(report.bytesRead == 4)
  #expect(report.byteLimitExceeded)
  #expect(records == ["a", "b"])
}

@Test func streamingReaderRejectsSymbolicLinksAndSpecialFiles() throws {
  // Catches transcript discovery being redirected or blocked by a FIFO.
  let directory = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let target = directory.appending(path: "target.jsonl")
  try Data("{}\n".utf8).write(to: target)
  let link = directory.appending(path: "link.jsonl")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
  expectNotRegularFile(at: link)

  let fifo = directory.appending(path: "pipe.jsonl")
  let result = fifo.withUnsafeFileSystemRepresentation { path in
    guard let path else { return Int32(-1) }
    return Darwin.mkfifo(path, 0o600)
  }
  #expect(result == 0)
  expectNotRegularFile(at: fifo)
}

@Test func observerProcessesExactlyFiftyMiBAndSkipsOneByteOver() throws {
  // Catches opening a file beyond the hard cap or rejecting the exact boundary.
  let root = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory)
  let sessions = root.appending(
    path: ".codex/sessions/2026/08/30",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let record = Data(
    """
    {"timestamp":"2999-01-01T00:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}}}

    """.utf8)
  let exact = sessions.appending(path: "a-exact.jsonl")
  try makeSparseFile(
    at: exact,
    prefix: record,
    byteCount: 52_428_800)
  let over = sessions.appending(path: "b-over.jsonl")
  try makeSparseFile(
    at: over,
    prefix: record,
    byteCount: 52_428_801)

  let report = try LocalUsageObserver(homeURL: root).scan(
    CodexRolloutParser.self,
    since: Date(timeIntervalSince1970: 1_000_000))

  #expect(LocalUsageObserver.maximumFileBytes == 52_428_800)
  #expect(report.summary.eventCount == 1)
  #expect(report.summary.totalTokens == 15)
  #expect(report.processedFileCount == 1)
  #expect(report.oversizedFileCount == 1)
  #expect(report.oversizedRecordCount == 1)
}

private func temporaryFile(contents: Data) throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appending(path: "records.jsonl")
  try contents.write(to: url)
  return url
}

private func makeSparseFile(at url: URL, prefix: Data, byteCount: UInt64) throws {
  FileManager.default.createFile(atPath: url.path, contents: nil)
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.write(contentsOf: prefix)
  try handle.truncate(atOffset: byteCount)
}

private func expectNotRegularFile(at url: URL) {
  do {
    _ = try JSONLStreamingReader().read(url: url) { _ in }
    Issue.record("Expected a non-regular file error")
  } catch let error as JSONLStreamingReaderError {
    #expect(error == .notRegularFile)
  } catch {
    Issue.record("Expected JSONLStreamingReaderError, got \(type(of: error))")
  }
}
