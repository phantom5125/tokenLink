import Foundation
import Testing
import TokenLinkCore
import TokenLinkProviders

@testable import TokenLinkApp

@Test func codexAnalyticsAttributionIsPrivacySafe() throws {
  var parser = CodexCostRecordParser()
  _ = parser.consume(
    analyticsRecord(
      #"{"timestamp":"2026-08-31T10:00:00Z","type":"session_meta","payload":{"id":"private-session-id","cwd":"/Users/alice/client/secret-project","thread_source":"user"}}"#
    ))
  _ = parser.consume(
    analyticsRecord(
      #"{"timestamp":"2026-08-31T10:00:01Z","type":"turn_context","payload":{"model":"gpt-test","effort":"high","cwd":"/Users/alice/client/secret-project"}}"#
    ))
  let parsed = parser.consume(
    analyticsRecord(
      #"{"timestamp":"2026-08-31T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":10,"output_tokens":20}}}}"#
    ))
  let usage = try #require(parsed)

  #expect(usage.projectName == "secret-project")
  #expect(usage.projectID != "/Users/alice/client/secret-project")
  #expect(!usage.projectID.contains("alice"))
  #expect(usage.sessionID != "private-session-id")
  #expect(usage.reasoningEffort == "high")
}

@Test func usageAnalyticsRefreshesOnlyChangedFilesAndReconcilesViews() throws {
  let root = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  let storage = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: storage)
  }
  let directory = root.appending(
    path: ".codex/sessions/2026/08/31",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appending(path: "rollout.jsonl")
  try Data(
    """
    {"timestamp":"2026-08-31T10:00:00Z","type":"session_meta","payload":{"id":"private-session-id","cwd":"/Users/alice/client/tokenLink","thread_source":"user"}}
    {"timestamp":"2026-08-31T10:00:01Z","type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
    {"timestamp":"2026-08-31T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":10,"output_tokens":20},"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":10,"output_tokens":20}}}}
    {"timestamp":"2026-08-31T10:03:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":100,"cache_write_input_tokens":20,"output_tokens":50},"last_token_usage":{"input_tokens":200,"cached_input_tokens":60,"cache_write_input_tokens":10,"output_tokens":30}}}}

    """.utf8
  ).write(to: file)
  let fixedNow = analyticsDate("2026-08-31T12:00:00Z")
  try FileManager.default.setAttributes(
    [.modificationDate: fixedNow],
    ofItemAtPath: file.path)
  let catalog = PriceCatalog(
    version: "analytics-test",
    effectiveDate: fixedNow,
    entries: [
      ModelPrice(
        provider: .codex,
        modelID: "gpt-test",
        aliases: [],
        currency: "USD",
        uncachedInputPerMillion: 1,
        cacheReadPerMillion: Decimal(string: "0.1"),
        cacheWritePerMillion: 1,
        outputPerMillion: 2,
        sourceURL: URL(string: "https://example.com/pricing")!)
    ])
  let service = UsageAnalyticsService(
    homeURL: root,
    store: UsageAnalyticsStore(directory: storage),
    catalog: catalog,
    now: { fixedNow })

  let first = try service.refresh()
  #expect(first.metadata.discoveredFileCount == 1)
  #expect(first.metadata.reparsedFileCount == 1)
  #expect(first.metadata.reusedFileCount == 0)
  #expect(first.metadata.retainedEventCount == 2)
  let bucket = try #require(first.buckets.first)
  #expect(first.buckets.count == 1)
  #expect(bucket.projectName == "tokenLink")
  #expect(bucket.effort == "high")
  #expect(bucket.totalTokens == 350)
  #expect(bucket.activeSeconds == 240)
  #expect(bucket.costNanoUSD > 0)

  let storedData = try Data(
    contentsOf: storage.appending(path: "usage-analytics-v1.json"))
  let storedText = String(decoding: storedData, as: UTF8.self)
  #expect(!storedText.contains("/Users/alice"))
  #expect(!storedText.contains("private-session-id"))
  #expect(!storedText.contains("client/tokenLink"))

  let second = try service.refresh()
  #expect(second.metadata.reparsedFileCount == 0)
  #expect(second.metadata.reusedFileCount == 1)
  #expect(second.buckets == first.buckets)

  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let snapshot = UsageAnalyticsQuery.snapshot(
    dataset: second,
    startDate: analyticsDate("2026-08-25T00:00:00Z"),
    endDate: analyticsDate("2026-08-31T00:00:00Z"),
    calendar: calendar)
  #expect(snapshot.current.totalTokens == 350)
  #expect(snapshot.current.activeSeconds == 240)
  #expect(snapshot.current.projectCount == 1)
  #expect(snapshot.current.modelCount == 1)
  #expect(snapshot.current.sessionCount == 1)
  #expect(snapshot.previous.totalTokens == 0)
  #expect(snapshot.calendarDays.count == 7)
  #expect(snapshot.attribution[.project]?.first?.label == "tokenLink")
  #expect(snapshot.attribution[.effort]?.first?.label == "High")
  #expect(snapshot.attribution[.session]?.count == 1)
  #expect(snapshot.attribution[.model]?.first?.totals.totalTokens == 350)
}

@Test func usageAnalyticsDeduplicatesClaudeMessagesAcrossFiles() throws {
  let root = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  let storage = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: storage)
  }
  let directory = root.appending(
    path: ".claude/projects/example",
    directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let record =
    #"{"timestamp":"2026-08-31T09:00:00Z","cwd":"/tmp/project","sessionId":"s1","message":{"id":"m1","model":"claude-test","usage":{"input_tokens":100,"output_tokens":20}}}"#
  let fixedNow = analyticsDate("2026-08-31T12:00:00Z")
  for name in ["a.jsonl", "b.jsonl"] {
    let file = directory.appending(path: name)
    try Data("\(record)\n".utf8).write(to: file)
    try FileManager.default.setAttributes(
      [.modificationDate: fixedNow],
      ofItemAtPath: file.path)
  }
  let catalog = PriceCatalog(
    version: "dedupe-test",
    effectiveDate: fixedNow,
    entries: [
      ModelPrice(
        provider: .claude,
        modelID: "claude-test",
        aliases: [],
        currency: "USD",
        uncachedInputPerMillion: 1,
        cacheReadPerMillion: 1,
        cacheWritePerMillion: 1,
        outputPerMillion: 1,
        sourceURL: URL(string: "https://example.com/pricing")!)
    ])
  let dataset = try UsageAnalyticsService(
    homeURL: root,
    store: UsageAnalyticsStore(directory: storage),
    catalog: catalog,
    now: { fixedNow }
  ).refresh()

  #expect(dataset.metadata.retainedEventCount == 1)
  #expect(dataset.buckets.map(\.totalTokens).reduce(0, +) == 120)
  let storedText = try String(
    contentsOf: storage.appending(path: "usage-analytics-v1.json"),
    encoding: .utf8)
  #expect(!storedText.contains(#""m1""#))
}

@Test func usageAnalyticsCalendarComparisonStaysAlignedAcrossDST() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
  let formatter = ISO8601DateFormatter()
  let start = formatter.date(from: "2026-03-08T08:00:00Z")!
  let end = formatter.date(from: "2026-03-14T07:00:00Z")!

  let snapshot = UsageAnalyticsQuery.snapshot(
    dataset: nil,
    startDate: start,
    endDate: end,
    calendar: calendar)

  #expect(calendar.component(.hour, from: snapshot.comparisonInterval.start) == 0)
  #expect(
    calendar.dateComponents(
      [.day],
      from: snapshot.comparisonInterval.start,
      to: snapshot.comparisonInterval.end
    ).day == 7)
}

@MainActor
@Test func usageAnalyticsCustomRangeClampsToRetainedHistoryAndToday() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let fixedNow = analyticsDate("2026-08-31T12:00:00Z")
  let model = UsageAnalyticsModel(
    calendar: calendar,
    now: { fixedNow },
    loader: {
      UsageAnalyticsDataset(
        buckets: [],
        earliestEventAt: nil,
        latestEventAt: nil,
        metadata: UsageAnalyticsRefreshMetadata(
          scannedAt: fixedNow,
          discoveredFileCount: 0,
          reparsedFileCount: 0,
          reusedFileCount: 0,
          skippedFileCount: 0,
          oversizedRecordCount: 0,
          retainedEventCount: 0,
          storageBytes: 0,
          catalogVersion: "test"))
    })

  model.setCustomRange(
    start: analyticsDate("2020-01-01T00:00:00Z"),
    end: analyticsDate("2030-01-01T00:00:00Z"))

  #expect(model.startDate == model.minimumSelectableDate)
  #expect(model.endDate == model.maximumSelectableDate)
}

@MainActor
@Test func usageAnalyticsReusesFreshDatasetWithinTTL() async {
  let fixedNow = analyticsDate("2026-08-31T12:00:00Z")
  let probe = UsageAnalyticsLoaderProbe()
  let model = UsageAnalyticsModel(
    now: { fixedNow },
    loader: { await probe.load(at: fixedNow) })

  await model.loadIfNeeded()
  await model.loadIfNeeded()

  #expect(await probe.calls == 1)
}

private func analyticsRecord(_ value: String) -> Data {
  Data(value.utf8)
}

private func analyticsDate(_ value: String) -> Date {
  ISO8601DateFormatter().date(from: value)!
}

private actor UsageAnalyticsLoaderProbe {
  private(set) var calls = 0

  func load(at date: Date) -> UsageAnalyticsDataset {
    calls += 1
    return UsageAnalyticsDataset(
      buckets: [],
      earliestEventAt: nil,
      latestEventAt: nil,
      metadata: UsageAnalyticsRefreshMetadata(
        scannedAt: date,
        discoveredFileCount: 0,
        reparsedFileCount: 0,
        reusedFileCount: 0,
        skippedFileCount: 0,
        oversizedRecordCount: 0,
        retainedEventCount: 0,
        storageBytes: 0,
        catalogVersion: "test"))
  }
}
