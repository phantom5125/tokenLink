import Foundation
import TokenLinkCore
import TokenLinkProviders

public enum UsageAnalyticsError: Error, Equatable, Sendable {
  case storageUnavailable
  case invalidStore
}

public struct UsageAnalyticsStore: Sendable {
  private let directory: URL
  private var databaseURL: URL {
    directory.appending(path: "usage-analytics-v1.json", directoryHint: .notDirectory)
  }

  public init(directory: URL) {
    self.directory = directory
  }

  public static func applicationSupport() throws -> Self {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true)
    return Self(
      directory: root.appending(path: "TokenLink", directoryHint: .isDirectory))
  }

  func load(now: Date) -> UsageAnalyticsDatabase {
    guard FileManager.default.fileExists(atPath: databaseURL.path),
      let data = try? Data(contentsOf: databaseURL),
      let value = try? Self.decoder.decode(UsageAnalyticsDatabase.self, from: data),
      value.schemaVersion == UsageAnalyticsDatabase.currentSchemaVersion
    else { return .empty(at: now) }
    return value
  }

  @discardableResult
  func save(_ database: UsageAnalyticsDatabase) throws -> Int {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    let data = try Self.encoder.encode(database)
    try data.write(to: databaseURL, options: .atomic)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: databaseURL.path)
    return data.count
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }()
}

public struct UsageAnalyticsService: @unchecked Sendable {
  public static let historyDays = 400
  public static let maximumRetainedEvents = 250_000
  public static let maximumEventsPerFile = 75_000
  public static let activeGapCap: TimeInterval = 300
  public static let isolatedEventSeconds = 60

  private let homeURL: URL
  private let fileManager: FileManager
  private let store: UsageAnalyticsStore
  private let catalog: PriceCatalog
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  public init(
    homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default,
    store: UsageAnalyticsStore,
    catalog: PriceCatalog,
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.homeURL = homeURL
    self.fileManager = fileManager
    self.store = store
    self.catalog = catalog
    self.calendar = calendar
    self.now = now
  }

  public func refresh() throws -> UsageAnalyticsDataset {
    try Task.checkCancellation()
    let scannedAt = now()
    let retentionStart =
      calendar.date(
        byAdding: .day,
        value: -Self.historyDays,
        to: calendar.startOfDay(for: scannedAt)) ?? .distantPast
    var database = store.load(now: scannedAt)
    let discovery = discoverFiles(since: retentionStart)
    var nextFiles: [String: UsageAnalyticsFileCache] = [:]
    var reparsedFileCount = 0
    var reusedFileCount = 0
    var skippedFileCount = discovery.skippedFileCount
    var oversizedRecordCount = 0

    for descriptor in discovery.files {
      try Task.checkCancellation()
      if let cached = database.files[descriptor.key],
        cached.provider == descriptor.provider,
        cached.byteCount == descriptor.byteCount,
        cached.modifiedAt == descriptor.modifiedAt
      {
        let retained = cached.events.filter { $0.timestamp >= retentionStart }
        nextFiles[descriptor.key] = UsageAnalyticsFileCache(
          provider: cached.provider,
          byteCount: cached.byteCount,
          modifiedAt: cached.modifiedAt,
          events: retained,
          oversizedRecordCount: cached.oversizedRecordCount)
        oversizedRecordCount += cached.oversizedRecordCount
        reusedFileCount += 1
        continue
      }

      do {
        let parsed = try parse(descriptor, since: retentionStart)
        nextFiles[descriptor.key] = parsed
        oversizedRecordCount += parsed.oversizedRecordCount
        reparsedFileCount += 1
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        skippedFileCount += 1
      }
    }

    database.files = trim(nextFiles, since: retentionStart)
    database.updatedAt = scannedAt
    let storageBytes = try store.save(database)
    let events = deduplicatedEvents(in: database)
    let metadata = UsageAnalyticsRefreshMetadata(
      scannedAt: scannedAt,
      discoveredFileCount: discovery.files.count,
      reparsedFileCount: reparsedFileCount,
      reusedFileCount: reusedFileCount,
      skippedFileCount: skippedFileCount,
      oversizedRecordCount: oversizedRecordCount,
      retainedEventCount: events.count,
      storageBytes: storageBytes,
      catalogVersion: catalog.version)
    return makeDataset(events: events, metadata: metadata)
  }

  private func parse(
    _ descriptor: TranscriptDescriptor,
    since: Date
  ) throws -> UsageAnalyticsFileCache {
    var events: [UsageAnalyticsStoredEvent] = []
    let report: JSONLReadReport
    switch descriptor.provider {
    case .codex:
      var parser = CodexCostRecordParser(
        fallbackProcessingTier: codexFallbackProcessingTier())
      report = try read(descriptor.url) { record in
        guard let usage = parser.consume(record), usage.timestamp >= since else { return }
        append(
          usage,
          descriptor: descriptor,
          to: &events)
      }
      parser.finish()
    case .claude:
      var parser = ClaudeCostRecordParser()
      report = try read(descriptor.url) { record in
        guard let usage = parser.consume(record), usage.timestamp >= since else { return }
        append(
          usage,
          descriptor: descriptor,
          to: &events)
      }
      parser.finish()
    case .kimi:
      var parser = KimiCostRecordParser()
      report = try read(descriptor.url) { record in
        guard let usage = parser.consume(record), usage.timestamp >= since else { return }
        append(
          usage,
          descriptor: descriptor,
          to: &events)
      }
      parser.finish()
    case .minimax, .glm, .openrouter, .deepseek:
      return UsageAnalyticsFileCache(
        provider: descriptor.provider,
        byteCount: descriptor.byteCount,
        modifiedAt: descriptor.modifiedAt,
        events: [],
        oversizedRecordCount: 0)
    }
    if events.count > Self.maximumEventsPerFile {
      events = Array(
        events.sorted { $0.timestamp < $1.timestamp }.suffix(Self.maximumEventsPerFile))
    }
    return UsageAnalyticsFileCache(
      provider: descriptor.provider,
      byteCount: descriptor.byteCount,
      modifiedAt: descriptor.modifiedAt,
      events: events,
      oversizedRecordCount: report.oversizedRecordCount)
  }

  private func read(
    _ url: URL,
    onRecord: (Data) -> Void
  ) throws -> JSONLReadReport {
    try JSONLStreamingReader().read(
      url: url,
      maximumBytes: LocalUsageObserver.maximumFileBytes,
      onRecord: onRecord)
  }

  private func append(
    _ usage: NormalizedModelUsage,
    descriptor: TranscriptDescriptor,
    to events: inout [UsageAnalyticsStoredEvent]
  ) {
    let projectID =
      usage.projectID == "unassigned"
      ? descriptor.fallbackProjectID : usage.projectID
    let projectName =
      usage.projectName == "Unassigned"
      ? descriptor.fallbackProjectName : usage.projectName
    let sessionID =
      usage.sessionID == "unknown"
      ? descriptor.fallbackSessionID : usage.sessionID
    let price = catalog.entry(provider: usage.provider, modelID: usage.modelID)
    let canonicalModelID = price?.modelID ?? usage.modelID
    let canonicalUsage = NormalizedModelUsage(
      provider: usage.provider,
      modelID: canonicalModelID,
      timestamp: usage.timestamp,
      uncachedInputTokens: usage.uncachedInputTokens,
      cacheReadTokens: usage.cacheReadTokens,
      cacheWriteTokens: usage.cacheWriteTokens,
      cacheWriteDuration: usage.cacheWriteDuration,
      outputTokens: usage.outputTokens,
      processingTier: usage.processingTier)
    let lineItem: ModelCostLineItem? = price.flatMap {
      guard $0.currency.uppercased() == "USD" else { return nil }
      return CostCalculator.lineItem(usage: canonicalUsage, price: $0)
    }
    events.append(
      UsageAnalyticsStoredEvent(
        timestamp: usage.timestamp,
        provider: usage.provider,
        projectID: projectID,
        projectName: projectName,
        modelID: canonicalModelID,
        effort: LocalUsageIdentity.effort(usage.reasoningEffort),
        sessionID: sessionID,
        processingTier: usage.processingTier,
        uncachedInputTokens: usage.uncachedInputTokens,
        cacheReadTokens: usage.cacheReadTokens,
        cacheWriteTokens: usage.cacheWriteTokens,
        outputTokens: usage.outputTokens,
        requestCount: 1,
        costNanoUSD: lineItem.map { nanoUSD($0.amount.value) } ?? 0,
        isPriced: lineItem != nil,
        deduplicationKey: usage.deduplicationKey.isEmpty
          ? ""
          : LocalUsageIdentity.hash(usage.deduplicationKey)))
  }

  private func makeDataset(
    events: [UsageAnalyticsStoredEvent],
    metadata: UsageAnalyticsRefreshMetadata
  ) -> UsageAnalyticsDataset {
    var buckets: [BucketKey: UsageAnalyticsBucket] = [:]
    let sorted = events.sorted { lhs, rhs in
      if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
      if lhs.sessionID != rhs.sessionID { return lhs.sessionID < rhs.sessionID }
      return lhs.modelID < rhs.modelID
    }
    for event in sorted {
      let hour =
        calendar.dateInterval(of: .hour, for: event.timestamp)?.start
        ?? event.timestamp
      let key = BucketKey(event: event, hour: hour)
      var bucket = buckets[key] ?? key.emptyBucket
      bucket.add(event)
      buckets[key] = bucket
    }

    var previousBySession: [String: Date] = [:]
    for event in sorted {
      let seconds: Int
      if let previous = previousBySession[event.sessionID] {
        let gap = event.timestamp.timeIntervalSince(previous)
        seconds =
          gap > 0 && gap <= Self.activeGapCap
          ? Int(gap.rounded(.down)) : Self.isolatedEventSeconds
      } else {
        seconds = Self.isolatedEventSeconds
      }
      previousBySession[event.sessionID] = event.timestamp
      let hour =
        calendar.dateInterval(of: .hour, for: event.timestamp)?.start
        ?? event.timestamp
      let key = BucketKey(event: event, hour: hour)
      buckets[key]?.addActiveSeconds(seconds)
    }

    let values = buckets.values.sorted { lhs, rhs in
      if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
      if lhs.provider != rhs.provider { return lhs.provider.rawValue < rhs.provider.rawValue }
      if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
      if lhs.modelID != rhs.modelID { return lhs.modelID < rhs.modelID }
      return lhs.sessionID < rhs.sessionID
    }
    return UsageAnalyticsDataset(
      buckets: values,
      earliestEventAt: sorted.first?.timestamp,
      latestEventAt: sorted.last?.timestamp,
      metadata: metadata)
  }

  private func deduplicatedEvents(
    in database: UsageAnalyticsDatabase
  ) -> [UsageAnalyticsStoredEvent] {
    var seen: Set<String> = []
    var values: [UsageAnalyticsStoredEvent] = []
    for key in database.files.keys.sorted() {
      guard let file = database.files[key] else { continue }
      for event in file.events {
        if !event.deduplicationKey.isEmpty,
          !seen.insert(event.deduplicationKey).inserted
        {
          continue
        }
        values.append(event)
      }
    }
    return values
  }

  private func trim(
    _ files: [String: UsageAnalyticsFileCache],
    since: Date
  ) -> [String: UsageAnalyticsFileCache] {
    var trimmed = files.mapValues { file in
      UsageAnalyticsFileCache(
        provider: file.provider,
        byteCount: file.byteCount,
        modifiedAt: file.modifiedAt,
        events: file.events.filter { $0.timestamp >= since },
        oversizedRecordCount: file.oversizedRecordCount)
    }
    struct EventLocation {
      let fileKey: String
      let index: Int
      let timestamp: Date
    }
    var locations: [EventLocation] = []
    for (key, file) in trimmed {
      locations.append(
        contentsOf: file.events.enumerated().map {
          EventLocation(fileKey: key, index: $0.offset, timestamp: $0.element.timestamp)
        })
    }
    guard locations.count > Self.maximumRetainedEvents else { return trimmed }
    locations.sort {
      if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
      if $0.fileKey != $1.fileKey { return $0.fileKey < $1.fileKey }
      return $0.index < $1.index
    }
    var retainedIndices: [String: Set<Int>] = [:]
    for location in locations.prefix(Self.maximumRetainedEvents) {
      retainedIndices[location.fileKey, default: []].insert(location.index)
    }
    for (key, file) in trimmed {
      let selected = retainedIndices[key] ?? []
      trimmed[key] = UsageAnalyticsFileCache(
        provider: file.provider,
        byteCount: file.byteCount,
        modifiedAt: file.modifiedAt,
        events: file.events.enumerated().compactMap {
          selected.contains($0.offset) ? $0.element : nil
        },
        oversizedRecordCount: file.oversizedRecordCount)
    }
    return trimmed
  }

  private func discoverFiles(since: Date) -> TranscriptDiscoveryResult {
    let roots: [(ProviderID, String)] = [
      (.codex, ".codex/sessions"),
      (.claude, ".claude/projects"),
      (.kimi, ".kimi-code/sessions"),
    ]
    var files: [TranscriptDescriptor] = []
    var skipped = 0
    for (provider, relative) in roots {
      let root = homeURL.appending(path: relative, directoryHint: .isDirectory)
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
        continue
      }
      guard isDirectory.boolValue else {
        skipped += 1
        continue
      }
      guard
        let enumerator = fileManager.enumerator(
          at: root,
          includingPropertiesForKeys: [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
            .isSymbolicLinkKey,
          ],
          options: [.skipsHiddenFiles],
          errorHandler: { _, _ in
            skipped += 1
            return false
          })
      else {
        skipped += 1
        continue
      }
      for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        guard
          let values = try? url.resourceValues(
            forKeys: [
              .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
              .isSymbolicLinkKey,
            ]),
          values.isRegularFile == true,
          values.isSymbolicLink != true,
          let modifiedAt = values.contentModificationDate,
          let byteCount = values.fileSize,
          modifiedAt >= since,
          byteCount <= LocalUsageObserver.maximumFileBytes
        else {
          skipped += 1
          continue
        }
        files.append(
          TranscriptDescriptor(
            provider: provider,
            url: url.standardizedFileURL,
            root: root,
            byteCount: byteCount,
            modifiedAt: modifiedAt))
      }
    }
    return TranscriptDiscoveryResult(
      files: files.sorted { $0.url.path < $1.url.path },
      skippedFileCount: skipped)
  }

  private func codexFallbackProcessingTier() -> CostProcessingTier {
    let url = homeURL.appending(path: ".codex/config.toml")
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize,
      size <= 1_048_576,
      let contents = try? String(contentsOf: url, encoding: .utf8)
    else { return .standard }
    return CodexConfiguration.processingTier(in: contents)
  }

  private func nanoUSD(_ value: Decimal) -> Int64 {
    let scaled = NSDecimalNumber(decimal: value * Decimal(1_000_000_000))
    if scaled.compare(NSDecimalNumber(value: Int64.max)) == .orderedDescending {
      return Int64.max
    }
    return max(0, scaled.int64Value)
  }
}

private struct TranscriptDiscoveryResult {
  let files: [TranscriptDescriptor]
  let skippedFileCount: Int
}

private struct TranscriptDescriptor {
  let provider: ProviderID
  let url: URL
  let byteCount: Int
  let modifiedAt: Date
  let key: String
  let fallbackProjectID: String
  let fallbackProjectName: String
  let fallbackSessionID: String

  init(
    provider: ProviderID,
    url: URL,
    root: URL,
    byteCount: Int,
    modifiedAt: Date
  ) {
    self.provider = provider
    self.url = url
    self.byteCount = byteCount
    self.modifiedAt = modifiedAt
    key = LocalUsageIdentity.hash(url.path, length: 32)
    let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
    let components = relative.split(separator: "/").map(String.init)
    let fallbackName = "Unassigned"
    fallbackProjectName = fallbackName
    fallbackProjectID =
      fallbackName == "Unassigned"
      ? "unassigned" : LocalUsageIdentity.hash("\(provider.rawValue):\(fallbackName)")
    let sessionSource =
      provider == .kimi && components.count > 1
      ? components[1] : url.deletingPathExtension().lastPathComponent
    fallbackSessionID = LocalUsageIdentity.hash("\(provider.rawValue):\(sessionSource)")
  }
}

private struct BucketKey: Hashable {
  let hour: Date
  let provider: ProviderID
  let projectID: String
  let projectName: String
  let modelID: String
  let effort: String
  let sessionID: String
  let processingTier: CostProcessingTier

  init(event: UsageAnalyticsStoredEvent, hour: Date) {
    self.hour = hour
    provider = event.provider
    projectID = event.projectID
    projectName = event.projectName
    modelID = event.modelID
    effort = event.effort
    sessionID = event.sessionID
    processingTier = event.processingTier
  }

  var emptyBucket: UsageAnalyticsBucket {
    UsageAnalyticsBucket(
      hour: hour,
      provider: provider,
      projectID: projectID,
      projectName: projectName,
      modelID: modelID,
      effort: effort,
      sessionID: sessionID,
      processingTier: processingTier,
      uncachedInputTokens: 0,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      outputTokens: 0,
      requestCount: 0,
      costNanoUSD: 0,
      pricedTokens: 0,
      activeSeconds: 0)
  }
}
