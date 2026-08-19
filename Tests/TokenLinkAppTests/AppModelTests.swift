import Foundation
import Testing
import TokenLinkCore
import TokenLinkDevice

@testable import TokenLinkApp

private actor CountingRefresher: AppRefreshing {
  private(set) var count = 0
  func refresh() async { count += 1 }
}

private actor StateSequenceLoader {
  private var states: [[ProviderID: ProviderState]]

  init(_ states: [[ProviderID: ProviderState]]) {
    self.states = states
  }

  func next() -> [ProviderID: ProviderState] {
    guard states.count > 1 else { return states.first ?? [:] }
    return states.removeFirst()
  }
}

private final class TestNow: @unchecked Sendable {
  var value: Date
  init(_ value: Date) { self.value = value }
  func callAsFunction() -> Date { value }
}

private actor TestBLETransport: BLETransport {
  nonisolated let eventStream: AsyncStream<BLETransportEvent>
  nonisolated let eventContinuation: AsyncStream<BLETransportEvent>.Continuation
  let failuresBeforeSuccess: Int
  private(set) var connectCount = 0
  private(set) var writes: [Data] = []

  init(failuresBeforeSuccess: Int = 0) {
    self.failuresBeforeSuccess = failuresBeforeSuccess
    (eventStream, eventContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
  }

  func discoveredIdentifiers() async throws -> [UUID] { [] }

  func connect(identifier: UUID) async throws {
    connectCount += 1
    if connectCount <= failuresBeforeSuccess {
      throw BluetoothTransportError.disconnected
    }
    eventContinuation.yield(.connected(identifier))
  }

  func writeWithResponse(_ data: Data) async throws {
    writes.append(data)
  }

  func disconnect() async {
    eventContinuation.yield(.disconnected(nil))
  }

  nonisolated func connectionEvents() -> AsyncStream<BLETransportEvent> {
    eventStream
  }

  func emitDisconnect(_ identifier: UUID) {
    eventContinuation.yield(.disconnected(identifier))
  }
}

private func snapshot(_ provider: ProviderID, remaining: Double) -> QuotaSnapshot {
  QuotaSnapshot(
    provider: provider,
    planLabel: nil,
    windows: [
      .init(
        id: "primary",
        label: "Primary",
        usedPercent: 100 - remaining,
        remainingPercent: remaining,
        remainingCount: nil,
        limitCount: nil,
        resetsAt: nil)
    ],
    source: provider == .codex ? .localAppServer : .apiKey,
    fetchedAt: Date(timeIntervalSince1970: 100))
}

@MainActor @Test func appModelHighlightsLowestHealthyWindow() async {
  let model = AppModel.preview(snapshots: [
    snapshot(.codex, remaining: 72),
    snapshot(.kimi, remaining: 24),
  ])
  #expect(model.highlight?.provider == .kimi)
  #expect(model.highlight?.window.remainingPercent == 24)
}

@MainActor @Test func manualRefreshIsThrottledForTenSeconds() async {
  let clock = TestNow(Date(timeIntervalSince1970: 100))
  let refresher = CountingRefresher()
  let model = AppModel(refresher: refresher, now: clock.callAsFunction)
  await model.refreshManually()
  await model.refreshManually()
  #expect(await refresher.count == 1)

  clock.value = Date(timeIntervalSince1970: 111)
  await model.refreshManually()
  #expect(await refresher.count == 2)
}

@MainActor @Test func schedulerUsesConfiguredFiveMinuteInterval() {
  let scheduler = RefreshScheduler(minutes: 5)
  #expect(scheduler.interval == .seconds(300))
}

@MainActor @Test func freshCodexRefreshAutomaticallySyncsBoundWatchWithBoundedRetry() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(failuresBeforeSuccess: 1)
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    now: { Date(timeIntervalSince1970: 200) },
    stateLoader: { _ in [.codex: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)

  await model.requestRefresh(reason: "Test refresh")

  #expect(await transport.connectCount == 2)
  #expect(await transport.writes.count == 1)
  guard case .synced = model.devicePhase else {
    Issue.record("Expected a successful automatic watch sync")
    return
  }
  model.stop()
}

@MainActor @Test func unsolicitedTransportDisconnectUpdatesWatchState() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport()
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [.codex: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)
  await model.requestRefresh(reason: "Test refresh")
  guard case .synced = model.devicePhase else {
    Issue.record("Expected the watch to be synced before disconnect")
    return
  }

  await transport.emitDisconnect(identifier)
  try? await Task.sleep(for: .milliseconds(20))

  #expect(model.devicePhase == .disconnected)
  model.stop()
}

@MainActor @Test func failedCodexRefreshMarksPreviouslySyncedWatchStale() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport()
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codex = snapshot(.codex, remaining: 72)
  let loader = StateSequenceLoader([
    [.codex: ProviderState(phase: .healthy, snapshot: codex)],
    [
      .codex: ProviderState(
        phase: .stale,
        snapshot: codex,
        error: .network("offline"))
    ],
  ])
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in await loader.next() },
    configuration: configuration,
    bluetoothTransport: transport)

  await model.requestRefresh(reason: "Healthy")
  guard case .synced = model.devicePhase else {
    Issue.record("Expected initial watch sync")
    return
  }
  await model.requestRefresh(reason: "Failed")

  #expect(model.devicePhase == .stale)
  model.stop()
}

@MainActor @Test func consecutiveFreshRefreshesReuseConnectedWatch() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport()
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [.codex: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)

  await model.requestRefresh(reason: "First")
  await model.requestRefresh(reason: "Second")

  #expect(await transport.connectCount == 1)
  #expect(await transport.writes.count == 2)
  model.stop()
}

@Test func diagnosticExporterRedactsEverySensitiveCategory() throws {
  let input: [String: Any] = [
    "api_key": "sk-live-value",
    "authorization": "Bearer live-token",
    "path": "/Users/alice/Library/Application Support/TokenLink/config.json",
    "username": "alice",
    "device": "32FA7010-3C2A-4C1D-AE44-123456789ABC",
    "account": "personal@example.com",
    "nested": ["secret": "should-not-survive"],
  ]
  let sanitized = DiagnosticExporter.sanitize(
    input,
    homeURL: URL(filePath: "/Users/alice", directoryHint: .isDirectory),
    accountLabels: ["personal@example.com"])
  let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
  let output = String(decoding: data, as: UTF8.self)

  for sensitive in [
    "sk-live-value",
    "live-token",
    "/Users/alice",
    "alice",
    "32FA7010-3C2A-4C1D-AE44-123456789ABC",
    "personal@example.com",
    "should-not-survive",
  ] {
    #expect(!output.contains(sensitive))
  }
}
