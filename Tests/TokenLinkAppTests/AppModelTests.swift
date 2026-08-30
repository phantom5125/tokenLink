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
  private var states: [[UUID: ProviderState]]

  init(_ states: [[UUID: ProviderState]]) {
    self.states = states
  }

  func next() -> [UUID: ProviderState] {
    guard states.count > 1 else { return states.first ?? [:] }
    return states.removeFirst()
  }
}

private final class TestNow: @unchecked Sendable {
  var value: Date
  init(_ value: Date) { self.value = value }
  func callAsFunction() -> Date { value }
}

private final class TestCodexDesktopActivator: CodexDesktopActivating, @unchecked Sendable {
  private(set) var openedThreadIDs: [String] = []

  func openCodexThread(_ threadID: String) async -> Bool {
    openedThreadIDs.append(threadID)
    return true
  }

  func activateCodexDesktop() -> Bool { true }
}

private actor TestBLETransport: BLETransport {
  nonisolated let eventStream: AsyncStream<BLETransportEvent>
  nonisolated let eventContinuation: AsyncStream<BLETransportEvent>.Continuation
  let failuresBeforeSuccess: Int
  let connectDelay: Duration?
  let writeDelay: Duration?
  let disconnectDelay: Duration?
  let noncancellableWriteDelays: [Duration]
  let capabilities: WatchCapabilities?
  private(set) var connectCount = 0
  private(set) var writeAttempts = 0
  private(set) var writes: [Data] = []

  init(
    failuresBeforeSuccess: Int = 0,
    connectDelay: Duration? = nil,
    writeDelay: Duration? = nil,
    disconnectDelay: Duration? = nil,
    noncancellableWriteDelays: [Duration] = [],
    capabilities: WatchCapabilities? = nil
  ) {
    self.failuresBeforeSuccess = failuresBeforeSuccess
    self.connectDelay = connectDelay
    self.writeDelay = writeDelay
    self.disconnectDelay = disconnectDelay
    self.noncancellableWriteDelays = noncancellableWriteDelays
    self.capabilities = capabilities
    (eventStream, eventContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
  }

  func discoveredIdentifiers() async throws -> [UUID] { [] }

  func connect(identifier: UUID) async throws {
    connectCount += 1
    if let connectDelay { try await Task.sleep(for: connectDelay) }
    if connectCount <= failuresBeforeSuccess {
      throw BluetoothTransportError.disconnected
    }
    eventContinuation.yield(.connected(identifier))
  }

  func writeWithResponse(_ data: Data) async throws {
    writeAttempts += 1
    if writeAttempts <= noncancellableWriteDelays.count {
      let delay = noncancellableWriteDelays[writeAttempts - 1]
      await Task.detached { try? await Task.sleep(for: delay) }.value
      try Task.checkCancellation()
    } else if let writeDelay {
      try await Task.sleep(for: writeDelay)
    }
    writes.append(data)
  }

  func readCapabilities() async throws -> WatchCapabilities? {
    capabilities
  }

  func disconnect() async {
    if let disconnectDelay { try? await Task.sleep(for: disconnectDelay) }
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

@MainActor @Test func macFocusTestUsesWatchSlotMappingAndPublishesOutcome() async {
  let store = WorkItemStore()
  await store.upsert(
    id: "thread-123",
    name: "TokenLink",
    source: .codex,
    state: .running,
    updatedAt: Date(timeIntervalSince1970: 90))
  let activator = TestCodexDesktopActivator()
  let model = AppModel(
    refresher: CountingRefresher(),
    now: { Date(timeIntervalSince1970: 100) },
    workItemStore: store,
    codexDesktopActivator: activator)

  await model.focusWorkItemOnMac(slot: 0)

  #expect(activator.openedThreadIDs == ["thread-123"])
  #expect(model.lastWatchFocusOutcome == .openedThread)
  #expect(model.lastWatchFocusAt == Date(timeIntervalSince1970: 100))
  model.stop()
}

@MainActor @Test func schedulerUsesConfiguredFiveMinuteInterval() {
  let scheduler = RefreshScheduler(minutes: 5)
  #expect(scheduler.interval == .seconds(300))
}

@MainActor @Test func explicitBindingCompletesBluetoothIdentityMigration() async throws {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
  let transport = TestBLETransport()
  var configuration = AppConfiguration.default
  configuration.requiresBluetoothRebinding = true
  let model = AppModel(
    refresher: CountingRefresher(),
    configuration: configuration,
    bluetoothTransport: transport)

  try await model.bindDevice(identifier)

  #expect(model.configuration.boundDeviceIdentifier == identifier)
  #expect(!model.configuration.requiresBluetoothRebinding)
  model.stop()
}

@MainActor @Test func freshCodexRefreshAutomaticallySyncsBoundWatchWithBoundedRetry() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(failuresBeforeSuccess: 1)
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    now: { Date(timeIntervalSince1970: 200) },
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
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

@MainActor @Test func freshSelectedKimiRefreshAutomaticallySyncsV2WatchWithoutHealthyCodex()
  async throws
{
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(
    capabilities: WatchCapabilities(protocolVersions: [1, 2], firmware: "0.2.0"))
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  configuration.watchSettings.syncedProviders = [.kimi]
  let kimiAccount = try #require(configuration.defaultAccount(for: .kimi))
  let kimi = snapshot(.kimi, remaining: 64)
  let model = AppModel(
    refresher: CountingRefresher(),
    now: { Date(timeIntervalSince1970: 200) },
    stateLoader: { _ in [kimiAccount.id: ProviderState(phase: .healthy, snapshot: kimi)] },
    configuration: configuration,
    bluetoothTransport: transport)

  await model.requestRefresh(reason: "Test refresh")

  let data = try #require(await transport.writes.last)
  let payload = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(payload.providerID == "kimi")
  model.stop()
}

@MainActor @Test func watchThemeChangeImmediatelyResyncsV2Payload() async throws {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(
    capabilities: WatchCapabilities(protocolVersions: [1, 2], firmware: "0.2.0"))
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = try #require(configuration.defaultAccount(for: .codex))
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    now: { Date(timeIntervalSince1970: 200) },
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)
  await model.requestRefresh(reason: "Initial refresh")
  #expect(await transport.writes.count == 1)

  try model.setWatchFaceTheme(.pet)
  for _ in 0..<50 {
    if await transport.writes.count == 2 { break }
    try? await Task.sleep(for: .milliseconds(5))
  }

  let data = try #require(await transport.writes.last)
  let payload = try JSONDecoder().decode(WatchPayloadV2.self, from: data)
  #expect(await transport.writes.count == 2)
  #expect(payload.settings?.theme == "pet")
  model.stop()
}

@MainActor @Test func unsolicitedTransportDisconnectUpdatesWatchState() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport()
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
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
  await model.requestRefresh(reason: "Reconnect")
  #expect(await transport.connectCount == 2)
  #expect(await transport.writes.count == 2)
  guard case .synced = model.devicePhase else {
    Issue.record("Expected the next refresh to reconnect and sync")
    return
  }
  model.stop()
}

@MainActor @Test func concurrentAutomaticAndManualSyncsCoalesce() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(writeDelay: .milliseconds(150))
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)

  let automatic = Task { await model.requestRefresh(reason: "Automatic") }
  for _ in 0..<50 {
    if await transport.writeAttempts == 1 { break }
    try? await Task.sleep(for: .milliseconds(5))
  }
  let manual = Task { await model.syncCodexNow() }
  await automatic.value
  await manual.value

  #expect(await transport.connectCount == 1)
  #expect(await transport.writeAttempts == 1)
  #expect(await transport.writes.count == 1)
  model.stop()
}

@MainActor @Test func unbindingCancelsInFlightSyncWithoutLateStateWrites() async throws {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(
    writeDelay: .seconds(2),
    disconnectDelay: .milliseconds(150))
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)

  let refresh = Task { await model.requestRefresh(reason: "Automatic") }
  for _ in 0..<50 {
    if await transport.writeAttempts == 1 { break }
    try? await Task.sleep(for: .milliseconds(5))
  }
  let unbind = Task { try await model.unbindDevice() }
  try? await Task.sleep(for: .milliseconds(20))
  let lateManualSync = Task { await model.syncCodexNow() }
  try await unbind.value
  await lateManualSync.value
  await refresh.value
  try? await Task.sleep(for: .milliseconds(20))

  #expect(model.devicePhase == .unbound)
  #expect(await transport.writeAttempts == 1)
  #expect(await transport.writes.isEmpty)
}

@MainActor @Test func lateCancelledSyncCannotClearReplacementSyncSlot() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport(
    noncancellableWriteDelays: [.milliseconds(100), .milliseconds(250), .milliseconds(250)])
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)

  let original = Task { await model.requestRefresh(reason: "Original") }
  for _ in 0..<50 {
    if await transport.writeAttempts == 1 { break }
    try? await Task.sleep(for: .milliseconds(5))
  }
  model.stop()
  let replacement = Task { await model.syncCodexNow() }
  for _ in 0..<50 {
    if await transport.writeAttempts == 2 { break }
    try? await Task.sleep(for: .milliseconds(5))
  }

  try? await Task.sleep(for: .milliseconds(130))
  let coalesced = Task { await model.syncCodexNow() }
  await original.value
  await replacement.value
  await coalesced.value

  #expect(await transport.writeAttempts == 2)
}

@MainActor @Test func failedCodexRefreshMarksPreviouslySyncedWatchStale() async {
  let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = TestBLETransport()
  var configuration = AppConfiguration.default
  configuration.boundDeviceIdentifier = identifier
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let loader = StateSequenceLoader([
    [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)],
    [
      codexAccount.id: ProviderState(
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
  let codexAccount = configuration.defaultAccount(for: .codex)!
  let codex = snapshot(.codex, remaining: 72)
  let model = AppModel(
    refresher: CountingRefresher(),
    stateLoader: { _ in [codexAccount.id: ProviderState(phase: .healthy, snapshot: codex)] },
    configuration: configuration,
    bluetoothTransport: transport)

  await model.requestRefresh(reason: "First")
  await model.requestRefresh(reason: "Second")

  #expect(await transport.connectCount == 1)
  #expect(await transport.writes.count == 2)
  model.stop()
}

private final class RefresherBuilderLog: @unchecked Sendable {
  var configurations: [AppConfiguration] = []
  var refreshers: [CountingRefresher] = []
}

@MainActor @Test func regionChangeRebuildsRefresherAndRefreshesWithNewConfiguration() async throws {
  let log = RefresherBuilderLog()
  let initial = CountingRefresher()
  let model = AppModel(
    refresher: initial,
    refresherBuilder: { configuration in
      log.configurations.append(configuration)
      let refresher = CountingRefresher()
      log.refreshers.append(refresher)
      return refresher
    })

  try model.setMiniMaxRegion(.china)
  try model.setGLMRegion(.china)

  #expect(log.configurations.map(\.miniMaxRegion) == [.china, .china])
  #expect(log.configurations.map(\.glmRegion) == [.global, .china])
  #expect(log.refreshers.count == 2)
  #expect(model.configurationRestartRequired == false)

  let replacement = try #require(log.refreshers.last)
  for _ in 0..<50 {
    if await replacement.count >= 1 { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await replacement.count >= 1)
  #expect(await initial.count == 0)
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

private actor AppModelFakeKeychain: KeychainClient {
  private struct Address: Hashable {
    let service: String
    let account: String
  }

  private var values: [Address: Data] = [:]

  func read(service: String, account: String) async throws -> Data? {
    values[Address(service: service, account: account)]
  }

  func readByService(service: String) async throws -> Data? { nil }

  func write(_ data: Data, service: String, account: String) async throws {
    values[Address(service: service, account: account)] = data
  }

  func delete(service: String, account: String) async throws {
    values[Address(service: service, account: account)] = nil
  }

  func set(_ value: String, service: String, account: String) {
    values[Address(service: service, account: account)] = Data(value.utf8)
  }

  func value(for account: String) -> String? {
    values[Address(service: KeychainVault.service, account: account)]
      .map { String(decoding: $0, as: UTF8.self) }
  }
}

private struct NoCLITokenReader: KimiTokenReading {
  func accessToken() async throws -> String? { nil }
}

private actor CountingClaudeTokenReader: ClaudeTokenReading {
  private(set) var readCount = 0

  func accessToken() async throws -> String? {
    readCount += 1
    return "claude-access-token"
  }
}

@MainActor @Test func addingCodexAccountIsRejected() {
  let model = AppModel(refresher: CountingRefresher())
  #expect(throws: ProviderFailure.self) {
    try model.addAccount(provider: .codex, label: "Second")
  }
}

@MainActor @Test func addAndRemoveAccountRebuildRefresher() async throws {
  let log = RefresherBuilderLog()
  let model = AppModel(
    refresher: CountingRefresher(),
    refresherBuilder: { configuration in
      log.configurations.append(configuration)
      return CountingRefresher()
    })
  let before = model.configuration.accounts.count

  let account = try model.addAccount(provider: .kimi, label: "Work")
  #expect(model.configuration.accounts.count == before + 1)
  #expect(log.configurations.last?.accounts.count == before + 1)

  try await model.removeAccount(id: account.id)
  #expect(model.configuration.accounts.count == before)
}

@MainActor @Test func removingDefaultAccountPromotesSuccessorKey() async throws {
  let client = AppModelFakeKeychain()
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLITokenReader())
  let model = AppModel(refresher: CountingRefresher(), vault: vault)
  let defaultAccount = try #require(model.configuration.defaultAccount(for: .minimax))
  try await model.setAPIKey("default-key", for: defaultAccount.id)
  let second = try model.addAccount(provider: .minimax, label: "Second")
  try await model.setAPIKey("second-key", for: second.id)

  #expect(await client.value(for: "minimax") == "default-key")
  #expect(await client.value(for: "minimax.\(second.id.uuidString)") == "second-key")

  try await model.removeAccount(id: defaultAccount.id)

  #expect(await client.value(for: "minimax") == "second-key")
  #expect(await client.value(for: "minimax.\(second.id.uuidString)") == nil)
  #expect(model.configuration.defaultAccount(for: .minimax)?.id == second.id)
}

@MainActor @Test func accountGroupsListEnabledAccountsPerProvider() throws {
  let model = AppModel(refresher: CountingRefresher())
  let second = try model.addAccount(provider: .kimi, label: "Work")

  let kimiGroup = try #require(model.accountGroups.first { $0.provider == .kimi })
  #expect(kimiGroup.accounts.count == 2)
  #expect(kimiGroup.accounts.first?.isDefault == true)
  #expect(kimiGroup.accounts.last?.isDefault == false)
  #expect(kimiGroup.accounts.last?.id == second.id)
  #expect(kimiGroup.accounts.last?.label == "Work")
  // Provider-level projection stays one row per provider for the current UI.
  #expect(model.orderedProviderRows.map(\.id) == [.codex, .kimi, .minimax, .glm])
}

@MainActor @Test func keyHintMasksStoredKeyForAccount() async throws {
  let client = AppModelFakeKeychain()
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLITokenReader())
  let model = AppModel(refresher: CountingRefresher(), vault: vault)
  let account = try #require(model.configuration.defaultAccount(for: .glm))
  try await model.setAPIKey("glm-secret-key-value", for: account.id)

  #expect(await model.keyHint(for: account.id) == "glm-secr…alue")
  #expect(await model.keyHint(for: UUID()) == nil)
}

@MainActor @Test func credentialStatesTrackEnvironmentFallback() async {
  let client = AppModelFakeKeychain()
  let vault = KeychainVault(
    client: client,
    kimiTokenReader: NoCLITokenReader(),
    environment: { $0 == "MINIMAX_API_KEY" ? "env-key" : nil })
  let model = AppModel(refresher: CountingRefresher(), vault: vault)

  await model.refreshCredentialStates()

  #expect(model.credentialConfigured[.minimax] == true)
  #expect(model.credentialConfigured[.glm] == false)
  let minimax = model.configuration.defaultAccount(for: .minimax)
  #expect(minimax.flatMap { model.credentialSourceByAccount[$0.id] } == .environmentVariable)
}

@MainActor @Test func legacyCredentialsRequireExplicitMigration() async throws {
  let client = AppModelFakeKeychain()
  await client.set(
    "legacy-glm-key",
    service: KeychainVault.legacyService,
    account: "glm")
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLITokenReader())
  var configuration = AppConfiguration.default
  configuration.legacyKeychainMigrationCompleted = false
  let model = AppModel(
    refresher: CountingRefresher(),
    configuration: configuration,
    vault: vault)
  let glm = try #require(configuration.defaultAccount(for: .glm))

  await model.refreshCredentialStates()
  #expect(model.credentialConfiguredByAccount[glm.id] == false)
  #expect(await client.value(for: "glm") == nil)

  let migrated = try await model.migrateLegacyCredentials()
  #expect(migrated == 1)
  #expect(model.configuration.legacyKeychainMigrationCompleted == true)
  #expect(model.credentialConfiguredByAccount[glm.id] == true)
  #expect(await client.value(for: "glm") == "legacy-glm-key")
}

@MainActor @Test func claudeKeychainIsReadOnlyAfterExplicitAuthorization() async throws {
  let claudeReader = CountingClaudeTokenReader()
  let vault = KeychainVault(
    client: AppModelFakeKeychain(),
    kimiTokenReader: NoCLITokenReader(),
    claudeTokenReader: claudeReader)
  var configuration = AppConfiguration.default
  configuration.accounts.append(
    ProviderAccount(provider: .claude, label: "Claude", enabled: true))
  let model = AppModel(
    refresher: CountingRefresher(),
    configuration: configuration,
    vault: vault)

  await model.refreshCredentialStates()
  #expect(await claudeReader.readCount == 0)
  #expect(model.configuration.claudeCredentialAccessAuthorized == false)

  try await model.authorizeClaudeCredentialAccess()
  #expect(await claudeReader.readCount == 1)
  #expect(model.configuration.claudeCredentialAccessAuthorized == true)

  // The authorization read is cached briefly, so its immediate status/quota
  // refresh cannot trigger a second macOS prompt.
  await model.refreshCredentialStates()
  #expect(await claudeReader.readCount == 1)

  try await model.stopUsingClaudeCredential()
  await model.refreshCredentialStates()
  #expect(await claudeReader.readCount == 1)
  #expect(model.configuration.claudeCredentialAccessAuthorized == false)
}
