import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkApp

@Test func codexRolloutParserExtractsTokenCountEvents() {
  let data = Data(
    """
    {"timestamp":"2026-08-25T01:00:00Z","type":"session_meta","payload":{"id":"x"}}
    {"timestamp":"2026-08-25T01:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":200,"total_tokens":1200}}}}
    {"timestamp":"2026-08-25T01:10:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":50,"total_tokens":550}}}}

    """
    .utf8)

  let events = CodexRolloutParser.parseEvents(from: data)

  #expect(events.count == 2)
  #expect(events[0].inputTokens == 1000)
  #expect(events[0].cachedInputTokens == 400)
  #expect(events[1].outputTokens == 50)
}

@Test func claudeTranscriptParserExtractsUsageAndDedupeKey() {
  let data = Data(
    """
    {"timestamp":"2026-08-25T01:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":900,"cache_creation_input_tokens":50}}}
    {"timestamp":"2026-08-25T01:01:00Z","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":900}}}
    {"timestamp":"2026-08-25T01:02:00Z","message":{"id":"m2","usage":{"input_tokens":300,"output_tokens":40}}}

    """
    .utf8)

  let events = ClaudeTranscriptParser.parseEvents(from: data)

  #expect(events.count == 3)
  #expect(events[0].cachedInputTokens == 950)
  #expect(events[0].dedupeKey == "m1")
  // Aggregation dedupes the repeated message id.
  let summary = LocalUsageAggregation.summarize(
    provider: .claude, events: events, since: .distantPast)
  #expect(summary.eventCount == 2)
  #expect(summary.inputTokens == 400)
}

@Test func kimiWireParserExtractsUsageRecords() {
  let data = Data(
    """
    {"type":"metadata","protocol_version":1,"created_at":1787620000000}
    {"type":"usage.record","agentId":"a1","model":"kimi-code/k3","usage":{"inputOther":3199,"output":204,"inputCacheRead":12288,"inputCacheCreation":0},"usageScope":"turn","time":1787630037215}

    """
    .utf8)

  let events = KimiWireParser.parseEvents(from: data)

  #expect(events.count == 1)
  #expect(events[0].inputTokens == 3199)
  #expect(events[0].cachedInputTokens == 12288)
  #expect(events[0].timestamp.timeIntervalSince1970 == 1_787_630_037.215)
}

@Test func aggregationFiltersEventsBeforeSince() {
  let old = TokenUsageEvent(
    timestamp: Date(timeIntervalSince1970: 100), inputTokens: 1, outputTokens: 1)
  let recent = TokenUsageEvent(
    timestamp: Date(timeIntervalSince1970: 10_000), inputTokens: 2, outputTokens: 2)
  let summary = LocalUsageAggregation.summarize(
    provider: .codex, events: [old, recent],
    since: Date(timeIntervalSince1970: 1_000))
  #expect(summary.eventCount == 1)
  #expect(summary.totalTokens == 4)
}

@Test func observerReadsOnlyRecentJsonlUnderDocumentedDirectories() async throws {
  let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let sessions = home.appending(path: ".codex/sessions/2026/08/25", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
  let fresh = sessions.appending(path: "rollout-fresh.jsonl")
  try Data(
    """
    {"timestamp":"2999-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"total_tokens":15}}}}

    """
    .utf8
  ).write(to: fresh)
  // A stale file whose mtime predates the window must be ignored.
  let stale = sessions.appending(path: "rollout-stale.jsonl")
  try Data(
    """
    {"timestamp":"2999-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":999,"cached_input_tokens":0,"output_tokens":999,"total_tokens":1998}}}}

    """
    .utf8
  ).write(to: stale)
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: stale.path)
  defer { try? FileManager.default.removeItem(at: home) }

  let observer = LocalUsageObserver(homeURL: home)
  let summary = observer.summarize(
    CodexRolloutParser.self, since: Date(timeIntervalSince1970: 1_000_000))

  #expect(summary.provider == .codex)
  #expect(summary.inputTokens == 10)
  #expect(summary.outputTokens == 5)
  #expect(summary.eventCount == 1)
}

@Test func observerReportsAnExistingButUnreadableTranscriptDirectory() throws {
  // Catches a permission failure being presented as if no transcript directory exists.
  let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let sessions = home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
  defer {
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: sessions.path)
    try? FileManager.default.removeItem(at: home)
  }
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o000],
    ofItemAtPath: sessions.path)

  let report = try LocalUsageObserver(homeURL: home).scan(
    CodexRolloutParser.self,
    since: .distantPast)

  #expect(report.unreadableFileCount == 1)
}

@Test func codexCostParserTracksModelsCumulativeDeltasAndChildBaseline() throws {
  // Catches charging cached input twice, repeated totals, or replayed parent totals.
  var parser = CodexCostRecordParser()
  #expect(
    parser.consume(
      jsonRecord(
        #"{"timestamp":"2026-08-30T00:00:00Z","type":"session_meta","payload":{"source":"vscode","thread_source":"user"}}"#
      ))
      == nil)
  #expect(
    parser.consume(
      jsonRecord(
        #"{"timestamp":"2026-08-30T00:00:01Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#
      ))
      == nil)
  let firstValue = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T00:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":20}}}}"#
    ))
  let first = try #require(firstValue)
  #expect(first.modelID == "gpt-5.4")
  #expect(first.uncachedInputTokens == 60)
  #expect(first.cacheReadTokens == 40)
  #expect(first.cacheWriteTokens == 5)
  #expect(first.outputTokens == 20)

  let repeated = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T00:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":20}}}}"#
    ))
  #expect(repeated == nil)
  _ = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T00:00:04Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#))
  let changedModelValue = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T00:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":60,"cache_write_input_tokens":8,"output_tokens":30}}}}"#
    ))
  let changedModel = try #require(changedModelValue)
  #expect(changedModel.modelID == "gpt-5.5")
  #expect(changedModel.uncachedInputTokens == 40)
  #expect(changedModel.cacheReadTokens == 20)
  #expect(changedModel.cacheWriteTokens == 3)
  #expect(changedModel.outputTokens == 10)

  let reset = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T00:00:06Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":2}}}}"#
    ))
  #expect(reset == nil)
  let afterResetValue = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T00:00:07Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":30,"cached_input_tokens":5,"cache_write_input_tokens":0,"output_tokens":5}}}}"#
    ))
  let afterReset = try #require(afterResetValue)
  #expect(afterReset.uncachedInputTokens == 15)
  #expect(afterReset.cacheReadTokens == 5)
  #expect(afterReset.outputTokens == 3)

  parser.finish()
  _ = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T01:00:00Z","type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{"depth":1,"parent_thread_id":"parent"}}},"thread_source":"subagent"}}"#
    ))
  _ = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T01:00:01Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#))
  let replayedParent = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T01:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":300,"cache_write_input_tokens":0,"output_tokens":100}}}}"#
    ))
  #expect(replayedParent == nil)
  let childDeltaValue = parser.consume(
    jsonRecord(
      #"{"timestamp":"2026-08-30T01:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":550,"cached_input_tokens":320,"cache_write_input_tokens":0,"output_tokens":110}}}}"#
    ))
  let childDelta = try #require(childDeltaValue)
  #expect(childDelta.uncachedInputTokens == 30)
  #expect(childDelta.cacheReadTokens == 20)
  #expect(childDelta.outputTokens == 10)
}

@Test func claudeCostParserKeepsFourBucketsAndDeduplicatesMessageIDs() throws {
  // Catches merging cache reads/writes into ordinary input or charging a duplicate message.
  var parser = ClaudeCostRecordParser()
  let record = jsonRecord(
    #"{"timestamp":"2026-08-30T02:00:00.000Z","type":"assistant","message":{"id":"message-1","model":"claude-sonnet-5","usage":{"input_tokens":100,"cache_read_input_tokens":200,"cache_creation_input_tokens":300,"output_tokens":40}}}"#
  )

  let usageValue = parser.consume(record)
  let usage = try #require(usageValue)
  #expect(usage.modelID == "claude-sonnet-5")
  #expect(usage.uncachedInputTokens == 100)
  #expect(usage.cacheReadTokens == 200)
  #expect(usage.cacheWriteTokens == 300)
  #expect(usage.cacheWriteDuration == nil)
  #expect(usage.outputTokens == 40)
  #expect(usage.deduplicationKey == "message-1")
  #expect(parser.consume(record) == nil)

  parser.finish()
  #expect(parser.consume(record) != nil)
}

@Test func kimiCostParserUsesTopLevelModelAndDirectBuckets() throws {
  // Catches losing the top-level model or folding Kimi cache creation into inputOther.
  var parser = KimiCostRecordParser()
  let usageValue = parser.consume(
    jsonRecord(
      #"{"type":"usage.record","time":1788048000000,"model":"kimi-code/k3","usage":{"inputOther":100,"inputCacheRead":200,"inputCacheCreation":300,"output":40},"usageScope":"turn"}"#
    ))
  let usage = try #require(usageValue)

  #expect(usage.modelID == "kimi-code/k3")
  #expect(usage.uncachedInputTokens == 100)
  #expect(usage.cacheReadTokens == 200)
  #expect(usage.cacheWriteTokens == 300)
  #expect(usage.outputTokens == 40)
  #expect(usage.timestamp == Date(timeIntervalSince1970: 1_788_048_000))
}

private func jsonRecord(_ value: String) -> Data {
  Data(value.utf8)
}
