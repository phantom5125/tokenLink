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
