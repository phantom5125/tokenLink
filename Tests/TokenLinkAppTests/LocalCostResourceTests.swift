import Foundation
import Testing

@testable import TokenLinkApp

private struct LocalCostResourceResult {
  let byteCount: Int
  let eventCount: Int
  let inputTokens: Int
  let cachedInputTokens: Int
  let outputTokens: Int

  var totalTokens: Int { inputTokens + outputTokens }
}

private enum LocalCostResourceWorkload {
  private static let fileBytes = 64 * 1_024 * 1_024
  private static let recordBytes = 4_096
  private static let recordsPerBatch = JSONLStreamingReader.chunkBytes / recordBytes

  static func run() throws -> LocalCostResourceResult {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString,
      directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "resource-workload.jsonl")

    let record = makeRecord()
    var batch = Data(capacity: JSONLStreamingReader.chunkBytes)
    for _ in 0..<recordsPerBatch {
      batch.append(record)
    }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    do {
      for _ in 0..<(fileBytes / batch.count) {
        try handle.write(contentsOf: batch)
      }
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }

    var eventCount = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    let report = try JSONLStreamingReader().read(url: url) { data in
      for event in CodexRolloutParser.parseEvents(from: data) {
        eventCount += 1
        inputTokens += event.inputTokens
        cachedInputTokens += event.cachedInputTokens
        outputTokens += event.outputTokens
      }
    }
    return LocalCostResourceResult(
      byteCount: report.bytesRead,
      eventCount: eventCount,
      inputTokens: inputTokens,
      cachedInputTokens: cachedInputTokens,
      outputTokens: outputTokens)
  }

  private static func makeRecord() -> Data {
    var data = Data(
      """
      {"timestamp":"2999-01-01T00:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":5}}}}
      """.utf8)
    precondition(data.count < recordBytes)
    data.append(Data(repeating: 0x20, count: recordBytes - data.count - 1))
    data.append(0x0A)
    precondition(data.count == recordBytes)
    return data
  }
}

@Test func localCostResourceWorkloadStreamsExpectedTotals() throws {
  guard ProcessInfo.processInfo.environment["TOKENLINK_RESOURCE_WORKLOAD"] == "1" else {
    return
  }

  let result = try LocalCostResourceWorkload.run()

  #expect(result.byteCount == 67_108_864)
  #expect(result.eventCount == 16_384)
  #expect(result.inputTokens == 163_840)
  #expect(result.cachedInputTokens == 32_768)
  #expect(result.outputTokens == 81_920)
  #expect(result.totalTokens == 245_760)
}
