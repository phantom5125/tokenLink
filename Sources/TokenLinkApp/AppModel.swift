import AppKit
import Foundation
import Network
import Observation
import TokenLinkCore
import TokenLinkDevice
import TokenLinkProviders

public protocol AppRefreshing: Sendable {
  func refresh() async
}

extension RefreshCoordinator: AppRefreshing {
  public func refresh() async {
    await refreshAll()
  }
}

private struct NoopRefresher: AppRefreshing {
  func refresh() async {}
}

public struct ProviderRow: Identifiable, Equatable, Sendable {
  public let id: ProviderID
  public let displayName: String
  public let state: ProviderState
}

public struct AccountRow: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let provider: ProviderID
  public let label: String
  public let isDefault: Bool
  public let state: ProviderState
}

public struct ProviderAccountGroup: Identifiable, Equatable, Sendable {
  public var id: ProviderID { provider }
  public let provider: ProviderID
  public let displayName: String
  public let accounts: [AccountRow]

  public init(provider: ProviderID, displayName: String, accounts: [AccountRow]) {
    self.provider = provider
    self.displayName = displayName
    self.accounts = accounts
  }
}

public struct ProviderHighlight: Equatable, Sendable {
  public let provider: ProviderID
  public let window: QuotaWindow
}

public struct AppEvent: Identifiable, Equatable, Sendable {
  public let id: String
  public let date: Date
  public let message: String

  init(date: Date, message: String) {
    self.id = "\(date.timeIntervalSince1970)-\(message)"
    self.date = date
    self.message = message
  }
}

@MainActor
@Observable
public final class AppModel {
  public private(set) var states: [UUID: ProviderState]
  public private(set) var devicePhase: DevicePhase
  public private(set) var events: [AppEvent] = []
  public private(set) var isRefreshing = false
  public private(set) var isDiscovering = false
  public private(set) var discoveredDeviceIdentifiers: [UUID] = []
  public private(set) var credentialConfigured: [ProviderID: Bool] = [:]
  public private(set) var credentialConfiguredByAccount: [UUID: Bool] = [:]
  public private(set) var credentialSourceByAccount: [UUID: CredentialSource] = [:]
  public private(set) var loginItemState: LoginItemState = .disabled
  public private(set) var configurationRestartRequired = false
  public var configuration: AppConfiguration
  /// Pace projections keyed by account id, refreshed together with states.
  public private(set) var burnEstimates: [UUID: BurnRateEstimate] = [:]

  @ObservationIgnored private var refresher: any AppRefreshing
  @ObservationIgnored private let refresherBuilder:
    (@Sendable (AppConfiguration) -> any AppRefreshing)?
  @ObservationIgnored private let stateLoader:
    @Sendable (TimeInterval) async -> [UUID: ProviderState]
  @ObservationIgnored private let estimateLoader: @Sendable () async -> [UUID: BurnRateEstimate]
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let configurationStore: ConfigurationStore?
  @ObservationIgnored private let vault: KeychainVault?
  @ObservationIgnored private let bluetoothTransport: (any BLETransport)?
  @ObservationIgnored private let loginController: LoginItemController?
  @ObservationIgnored private var bridge: DeviceBridge?
  @ObservationIgnored private var scheduler: RefreshScheduler
  @ObservationIgnored private var wakeObserver: NSObjectProtocol?
  @ObservationIgnored private var pathMonitor: NWPathMonitor?
  @ObservationIgnored private var bridgeEventTask: Task<Void, Never>?
  @ObservationIgnored private var watchSyncTask: Task<Void, Never>?
  @ObservationIgnored private var watchSyncToken: UUID?
  @ObservationIgnored private var bindingGeneration: UInt64 = 0
  @ObservationIgnored private var hasSeenNetworkState = false
  @ObservationIgnored private var networkWasAvailable = false
  @ObservationIgnored private var lastManualRefresh: Date?
  @ObservationIgnored private var started = false
  @ObservationIgnored private var notificationPolicy = NotificationPolicy()
  @ObservationIgnored private let notificationManager: (any NotificationManaging)?
  @ObservationIgnored private var isChangingBinding = false

  public init(
    refresher: any AppRefreshing,
    refresherBuilder: (@Sendable (AppConfiguration) -> any AppRefreshing)? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    stateLoader: @escaping @Sendable (TimeInterval) async -> [UUID: ProviderState] = { _ in
      [:]
    },
    estimateLoader: @escaping @Sendable () async -> [UUID: BurnRateEstimate] = { [:] },
    configuration: AppConfiguration = .default,
    configurationStore: ConfigurationStore? = nil,
    vault: KeychainVault? = nil,
    bluetoothTransport: (any BLETransport)? = nil,
    loginController: LoginItemController? = nil,
    notificationManager: (any NotificationManaging)? = nil
  ) {
    self.refresher = refresher
    self.refresherBuilder = refresherBuilder
    self.now = now
    self.stateLoader = stateLoader
    self.estimateLoader = estimateLoader
    self.configuration = configuration
    self.configurationStore = configurationStore
    self.vault = vault
    self.bluetoothTransport = bluetoothTransport
    self.loginController = loginController
    self.notificationManager = notificationManager
    self.states = [:]
    self.devicePhase = configuration.boundDeviceIdentifier == nil ? .unbound : .disconnected
    self.scheduler = RefreshScheduler(minutes: configuration.refreshMinutes)
    if let identifier = configuration.boundDeviceIdentifier,
      let bluetoothTransport
    {
      self.bridge = DeviceBridge(
        transport: bluetoothTransport,
        boundIdentifier: identifier)
    }
    if let loginController {
      self.loginItemState = loginController.state
    }
  }

  public static func preview(snapshots: [QuotaSnapshot]) -> AppModel {
    let model = AppModel(refresher: NoopRefresher())
    var keyed: [UUID: ProviderState] = [:]
    for snapshot in snapshots {
      guard let account = model.configuration.defaultAccount(for: snapshot.provider)
      else { continue }
      keyed[account.id] = ProviderState(phase: .healthy, snapshot: snapshot)
    }
    model.states = keyed
    return model
  }

  public static func live() -> AppModel {
    let configurationStore = try? ConfigurationStore.applicationSupport()
    let configuration = (try? configurationStore?.load()) ?? .default
    let vault = KeychainVault()
    let http = URLSessionHTTPClient()
    let store = ProviderStore()
    let makeCoordinator: @Sendable (AppConfiguration) -> RefreshCoordinator = { configuration in
      RefreshCoordinator(
        providers: makeProviders(configuration: configuration, http: http, vault: vault),
        store: store)
    }
    return AppModel(
      refresher: makeCoordinator(configuration),
      refresherBuilder: makeCoordinator,
      stateLoader: { refreshIntervalSeconds in
        await store.allStates(refreshIntervalSeconds: refreshIntervalSeconds)
      },
      estimateLoader: { await store.allBurnEstimates() },
      configuration: configuration,
      configurationStore: configurationStore,
      vault: vault,
      bluetoothTransport: CoreBluetoothTransport(),
      loginController: LoginItemController(),
      // UNUserNotificationCenter requires an app bundle; stay silent when
      // running unpackaged (e.g. `swift run`).
      notificationManager: Bundle.main.bundleURL.pathExtension == "app"
        ? SystemNotificationManager() : NullNotificationManager())
  }

  nonisolated private static func makeProviders(
    configuration: AppConfiguration,
    http: any HTTPClient,
    vault: any CredentialReader
  ) -> [AccountProvider] {
    var providers: [AccountProvider] = []
    for account in configuration.accounts where account.enabled {
      let isDefault = configuration.isDefaultAccount(account)
      // Codex and Claude rely on local CLI sign-ins and stay single-instance.
      if account.provider == .codex || account.provider == .claude, !isDefault { continue }
      let provider: any QuotaProvider
      switch account.provider {
      case .codex:
        provider = CodexProvider(
          executable: resolveCodexExecutable(
            configuredPath: configuration.codexPath))
      case .kimi, .minimax, .glm, .claude:
        guard let spec = ProviderRegistry.spec(for: account.provider) else { continue }
        let region: String?
        switch account.provider {
        case .minimax: region = configuration.miniMaxRegion.rawValue
        case .glm: region = configuration.glmRegion.rawValue
        default: region = nil
        }
        provider = SpecDrivenProvider(
          spec: spec,
          region: region,
          credentialAccount: KeychainVault.keychainAccountName(
            provider: account.provider,
            accountID: account.id,
            isDefault: isDefault),
          http: http,
          credentials: vault)
      }
      providers.append(AccountProvider(accountID: account.id, provider: provider))
    }
    return providers
  }

  /// Enabled accounts grouped by provider, in `ProviderID.allCases` order.
  public var accountGroups: [ProviderAccountGroup] {
    ProviderID.allCases.compactMap { provider in
      let rows =
        configuration.accounts
        .filter { $0.provider == provider && $0.enabled }
        .map { account in
          AccountRow(
            id: account.id,
            provider: provider,
            label: account.label,
            isDefault: configuration.isDefaultAccount(account),
            state: states[account.id] ?? ProviderState(phase: .disabled))
        }
      guard !rows.isEmpty else { return nil }
      return ProviderAccountGroup(
        provider: provider,
        displayName: Self.displayName(for: provider),
        accounts: rows)
    }
  }

  /// Minimal single-account projection used by the current UI: one row per
  /// provider, backed by its default account.
  public var orderedProviderRows: [ProviderRow] {
    accountGroups.compactMap { group in
      guard let row = group.accounts.first(where: \.isDefault) else { return nil }
      return ProviderRow(
        id: group.provider,
        displayName: group.displayName,
        state: row.state)
    }
  }

  /// Pace projection for a provider's default account (nil when the data is
  /// too thin or the window is not burning).
  public func burnEstimate(for provider: ProviderID) -> BurnRateEstimate? {
    guard let account = configuration.defaultAccount(for: provider) else { return nil }
    return burnEstimates[account.id]
  }

  public var highlight: ProviderHighlight? {
    orderedProviderRows
      .filter { $0.state.phase == .healthy }
      .compactMap { row -> ProviderHighlight? in
        guard let window = row.state.snapshot?.mostConstrainedWindow else { return nil }
        return ProviderHighlight(provider: row.id, window: window)
      }
      .min { $0.window.remainingPercent < $1.window.remainingPercent }
  }

  public var menuBarLabel: String {
    guard let highlight else { return "TokenLink" }
    return
      "\(Self.displayName(for: highlight.provider)) \(Int(highlight.window.remainingPercent.rounded()))%"
  }

  public var deviceStatusText: String {
    let key: L10n.Key =
      switch devicePhase {
      case .unbound: .deviceUnbound
      case .disconnected: .deviceDisconnected
      case .scanning: .deviceScanning
      case .connecting: .deviceConnecting
      case .connected: .deviceConnected
      case .syncing: .deviceSyncing
      case .synced: .deviceSynced
      case .stale: .deviceStale
      }
    return L10n.text(key, language: currentLanguage)
  }

  /// Effective UI language: explicit preference wins, otherwise the system.
  public var currentLanguage: AppLanguage {
    AppLanguage.resolve(preference: configuration.appLanguage)
  }

  public func text(_ key: L10n.Key) -> String {
    L10n.text(key, language: currentLanguage)
  }

  /// Persists an `AppLanguage` raw value (nil = follow the system) and applies
  /// it immediately through the observable configuration.
  public func setAppLanguage(_ preference: String?) throws {
    configuration.appLanguage = preference
    try saveConfiguration()
  }

  public func start() async {
    guard !started else { return }
    started = true
    await ensureBridgeObservation()
    await requestRefresh(reason: "Started")
    await refreshCredentialStates()
    scheduler.start { [weak self] in
      await self?.requestRefresh(reason: "Scheduled refresh")
    }
    observeWake()
    observeNetwork()
  }

  public func stop() {
    scheduler.stop()
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
    }
    wakeObserver = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    bindingGeneration &+= 1
    watchSyncTask?.cancel()
    watchSyncTask = nil
    watchSyncToken = nil
    bridgeEventTask?.cancel()
    bridgeEventTask = nil
    if let bridge {
      Task { await bridge.stopObservingTransport() }
    }
    started = false
  }

  public func refreshManually() async {
    let date = now()
    if let lastManualRefresh,
      date.timeIntervalSince(lastManualRefresh) < 10
    {
      return
    }
    lastManualRefresh = date
    await requestRefresh(reason: "Manual refresh")
  }

  public func requestRefresh(reason: String) async {
    guard !isRefreshing else { return }
    await ensureBridgeObservation()
    isRefreshing = true
    await refresher.refresh()
    let previousStates = states
    states = await stateLoader(TimeInterval(configuration.refreshMinutes * 60))
    burnEstimates = await estimateLoader()
    await postNotifications(previousStates: previousStates)
    if bridge != nil,
      let codexAccount = configuration.defaultAccount(for: .codex),
      states[codexAccount.id]?.phase == .healthy
    {
      await syncCodex(allowStale: false, attempts: 2, automatic: true)
    } else if case .synced = devicePhase {
      devicePhase = .stale
    }
    isRefreshing = false
    record(reason)
  }

  private func postNotifications(previousStates: [UUID: ProviderState]) async {
    guard configuration.notificationsEnabled, let notificationManager else { return }
    _ = previousStates  // transitions are tracked inside the policy's latches
    let strings = NotificationPolicy.Strings(
      lowQuotaTitle: text(.notifyLowQuotaTitle),
      lowQuotaBody: text(.notifyLowQuotaBody),
      authFailureTitle: text(.notifyAuthFailureTitle),
      authFailureBody: text(.notifyAuthFailureBody),
      resetTitle: text(.notifyResetTitle),
      resetBody: text(.notifyResetBody))
    let accounts = configuration.accounts
    let notifications = notificationPolicy.evaluate(
      current: states,
      nameForAccount: { accountID in
        accounts.first { $0.id == accountID }.map {
          Self.displayName(for: $0.provider)
        } ?? "?"
      },
      strings: strings,
      now: now())
    guard !notifications.isEmpty else { return }
    await notificationManager.requestAuthorizationIfNeeded()
    for notification in notifications {
      await notificationManager.post(notification)
    }
  }

  /// Writes (or clears, when empty) the key of the provider's default account.
  public func saveAPIKey(_ value: String, for provider: ProviderID) async throws {
    guard let account = configuration.defaultAccount(for: provider) else { return }
    try await setAPIKey(value, for: account.id)
  }

  public func deleteAPIKey(for provider: ProviderID) async throws {
    try await saveAPIKey("", for: provider)
  }

  public func setAPIKey(_ value: String, for accountID: UUID) async throws {
    guard let vault,
      let account = configuration.accounts.first(where: { $0.id == accountID })
    else { return }
    // Claude only uses the local CLI OAuth token or an env var; Anthropic
    // pay-as-you-go keys do not work for subscription quota, so there is
    // nothing to store.
    guard account.provider != .claude else {
      throw ProviderFailure.configuration(
        "Claude uses the Claude Code CLI sign-in; TokenLink does not store a key.")
    }
    let name = KeychainVault.keychainAccountName(
      provider: account.provider,
      accountID: account.id,
      isDefault: configuration.isDefaultAccount(account))
    if value.isEmpty {
      try await vault.deleteAPIKey(forAccount: name)
    } else {
      try await vault.setAPIKey(value, forAccount: name)
    }
    await refreshCredentialStates()
    record("Updated \(Self.displayName(for: account.provider)) credentials")
  }

  /// Display-only masked hint (head/tail) of the stored key; never the key.
  public func keyHint(for accountID: UUID) async -> String? {
    guard let vault,
      let account = configuration.accounts.first(where: { $0.id == accountID })
    else { return nil }
    return try? await vault.keyHint(
      for: account,
      isDefault: configuration.isDefaultAccount(account))
  }

  /// Adds an additional account for a provider. Codex is backed by the local
  /// CLI sign-in and stays single-account.
  @discardableResult
  public func addAccount(provider: ProviderID, label: String) throws -> ProviderAccount {
    guard provider != .codex, provider != .claude else {
      throw ProviderFailure.configuration(
        "Codex and Claude use local CLI sign-ins and support a single account.")
    }
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = ProviderAccount(
      provider: provider,
      label: trimmed.isEmpty ? Self.displayName(for: provider) : trimmed)
    configuration.accounts.append(account)
    try saveConfiguration()
    rebuildRefresher(reason: "Account added; refreshing")
    Task { await refreshCredentialStates() }
    return account
  }

  /// Removes an account and its stored key. When the default account is
  /// removed, the next account is promoted and its key moved to the default
  /// Keychain name so it keeps working.
  public func removeAccount(id: UUID) async throws {
    guard let index = configuration.accounts.firstIndex(where: { $0.id == id })
    else { return }
    let account = configuration.accounts[index]
    let wasDefault = configuration.isDefaultAccount(account)
    if let vault {
      try await vault.deleteAPIKey(for: account, isDefault: wasDefault)
    }
    configuration.accounts.remove(at: index)
    if wasDefault, let vault,
      let successor = configuration.defaultAccount(for: account.provider)
    {
      let successorName = KeychainVault.keychainAccountName(
        provider: successor.provider, accountID: successor.id, isDefault: false)
      if let key = try await vault.apiKey(forAccount: successorName) {
        try await vault.setAPIKey(key, forAccount: account.provider.rawValue)
        try await vault.deleteAPIKey(forAccount: successorName)
      }
    }
    try saveConfiguration()
    rebuildRefresher(reason: "Account removed; refreshing")
    await refreshCredentialStates()
    record("Removed \(Self.displayName(for: account.provider)) account")
  }

  public func refreshCredentialStates() async {
    guard let vault else { return }
    var byAccount: [UUID: Bool] = [:]
    var sources: [UUID: CredentialSource] = [:]
    for account in configuration.accounts where account.provider != .codex {
      let name = KeychainVault.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: configuration.isDefaultAccount(account))
      let key = (try? await vault.apiKey(forAccount: name)) ?? nil
      if let key, !key.isEmpty {
        byAccount[account.id] = true
        sources[account.id] = .apiKey
        continue
      }
      if ProviderRegistry.spec(for: account.provider)?.allowsCLICredential == true {
        let token = (try? await vault.cliAccessToken(for: account.provider)) ?? nil
        if let token, !token.isEmpty {
          byAccount[account.id] = true
          sources[account.id] = .cliCredential
          continue
        }
      }
      let envKey = (try? await vault.environmentAPIKey(for: account.provider)) ?? nil
      if envKey != nil {
        byAccount[account.id] = true
        sources[account.id] = .environmentVariable
      } else {
        byAccount[account.id] = false
      }
    }
    credentialConfiguredByAccount = byAccount
    credentialSourceByAccount = sources
    var byProvider: [ProviderID: Bool] = [:]
    for provider in ProviderID.allCases where provider != .codex {
      byProvider[provider] =
        configuration.defaultAccount(for: provider).map { byAccount[$0.id] == true }
        ?? false
    }
    credentialConfigured = byProvider
  }

  public func discoverDevices() async {
    guard let bluetoothTransport else { return }
    isDiscovering = true
    discoveredDeviceIdentifiers = []
    devicePhase = .scanning
    do {
      discoveredDeviceIdentifiers = try await bluetoothTransport.discoveredIdentifiers()
      devicePhase = configuration.boundDeviceIdentifier == nil ? .unbound : .disconnected
      record("Bluetooth discovery completed")
    } catch {
      devicePhase = .disconnected
      record("Bluetooth discovery failed")
    }
    isDiscovering = false
  }

  public func bindDevice(_ identifier: UUID) async throws {
    guard let bluetoothTransport, !isChangingBinding else { return }
    isChangingBinding = true
    defer { isChangingBinding = false }
    bindingGeneration &+= 1
    let previousBridge = bridge
    await cancelActiveWatchSync()
    bridgeEventTask?.cancel()
    bridgeEventTask = nil
    await previousBridge?.stopObservingTransport()
    await previousBridge?.disconnect()
    configuration.boundDeviceIdentifier = identifier
    bridge = DeviceBridge(
      transport: bluetoothTransport,
      boundIdentifier: identifier)
    devicePhase = .disconnected
    try saveConfiguration()
    await ensureBridgeObservation()
    discoveredDeviceIdentifiers = []
    record("Bound StopWatch")
  }

  public func unbindDevice() async throws {
    guard !isChangingBinding else { return }
    isChangingBinding = true
    defer { isChangingBinding = false }
    bindingGeneration &+= 1
    let previousBridge = bridge
    await cancelActiveWatchSync()
    bridgeEventTask?.cancel()
    bridgeEventTask = nil
    await previousBridge?.stopObservingTransport()
    await previousBridge?.disconnect()
    bridge = nil
    configuration.boundDeviceIdentifier = nil
    devicePhase = .unbound
    try saveConfiguration()
    record("Unbound StopWatch")
  }

  public func syncCodexNow() async {
    await ensureBridgeObservation()
    await syncCodex(allowStale: true, attempts: 2, automatic: false)
  }

  public func setProvider(_ provider: ProviderID, enabled: Bool) throws {
    if enabled {
      if configuration.accounts.contains(where: { $0.provider == provider }) {
        for index in configuration.accounts.indices
        where configuration.accounts[index].provider == provider {
          configuration.accounts[index].enabled = true
        }
      } else {
        configuration.accounts.append(
          ProviderAccount(
            provider: provider,
            label: Self.displayName(for: provider)))
      }
    } else {
      for index in configuration.accounts.indices
      where configuration.accounts[index].provider == provider {
        configuration.accounts[index].enabled = false
      }
    }
    configurationRestartRequired = true
    try saveConfiguration()
  }

  public func setCodexPath(_ path: String?) throws {
    let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
    configuration.codexPath = (trimmed?.isEmpty == false) ? trimmed : nil
    configurationRestartRequired = true
    try saveConfiguration()
  }

  public func setMiniMaxRegion(_ region: MiniMaxRegion) throws {
    configuration.miniMaxRegion = region
    try saveConfiguration()
    rebuildRefresher()
  }

  public func setGLMRegion(_ region: GLMRegion) throws {
    configuration.glmRegion = region
    try saveConfiguration()
    rebuildRefresher()
  }

  private func rebuildRefresher(
    reason: String = "Region change applied; refreshing with the new endpoint"
  ) {
    guard let refresherBuilder else { return }
    refresher = refresherBuilder(configuration)
    record(reason)
    Task {
      await requestRefresh(reason: reason)
    }
  }

  public func setRefreshMinutes(_ minutes: Int) throws {
    let replacement = RefreshScheduler(minutes: minutes)
    configuration.refreshMinutes = replacement.minutes
    scheduler.stop()
    scheduler = replacement
    if started {
      scheduler.start { [weak self] in
        await self?.requestRefresh(reason: "Scheduled refresh")
      }
    }
    try saveConfiguration()
  }

  public func setLoginItemEnabled(_ enabled: Bool) throws {
    guard let loginController else { return }
    loginItemState = try loginController.setEnabled(enabled)
  }

  public func setNotificationsEnabled(_ enabled: Bool) throws {
    configuration.notificationsEnabled = enabled
    try saveConfiguration()
  }

  public func diagnosticObject() -> [String: Any] {
    [
      "generated_at": ISO8601DateFormatter().string(from: now()),
      "configuration": [
        "enabled_providers": configuration.enabledProviders.map(\.rawValue).sorted(),
        "refresh_minutes": configuration.refreshMinutes,
        "bound_device": configuration.boundDeviceIdentifier?.uuidString ?? "none",
        "codex_path": configuration.codexPath ?? "automatic",
        "minimax_region": configuration.miniMaxRegion.rawValue,
        "glm_region": configuration.glmRegion.rawValue,
      ],
      "providers": orderedProviderRows.map { row in
        let remaining: Any =
          if let value = row.state.snapshot?
            .mostConstrainedWindow?.remainingPercent
          { value } else { NSNull() }
        let fetchedAt: Any =
          if let snapshot = row.state.snapshot {
            ISO8601DateFormatter().string(from: snapshot.fetchedAt)
          } else { NSNull() }
        let errorKind: Any =
          if let value = row.state.error?.kind.rawValue {
            value
          } else { NSNull() }
        return [
          "provider": row.id.rawValue,
          "phase": row.state.phase.rawValue,
          "remaining_percent": remaining,
          "fetched_at": fetchedAt,
          "error_kind": errorKind,
        ] as [String: Any]
      },
      "device_phase": deviceStatusText,
      "events": events.map { ["date": $0.date.timeIntervalSince1970, "message": $0.message] },
    ]
  }

  public func exportDiagnostics(to url: URL) throws {
    try DiagnosticExporter.write(diagnosticObject(), to: url)
  }

  private func saveConfiguration() throws {
    try configurationStore?.save(configuration)
  }

  private func syncCodex(
    allowStale: Bool,
    attempts: Int,
    automatic: Bool
  ) async {
    guard !isChangingBinding else { return }
    if let active = watchSyncTask {
      await active.value
      return
    }
    guard let bridge,
      let codexAccount = configuration.defaultAccount(for: .codex),
      let state = states[codexAccount.id],
      state.phase == .healthy || (allowStale && state.phase == .stale),
      let snapshot = state.snapshot,
      let payload = try? LegacyWatchProjection.encode(snapshot: snapshot, now: now())
    else { return }

    let generation = bindingGeneration
    let boundedAttempts = min(2, max(1, attempts))
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performWatchSync(
        bridge: bridge,
        payload: payload,
        generation: generation,
        attempts: boundedAttempts,
        automatic: automatic)
    }
    let token = UUID()
    watchSyncTask = task
    watchSyncToken = token
    await task.value
    if watchSyncToken == token {
      watchSyncTask = nil
      watchSyncToken = nil
    }
  }

  private func performWatchSync(
    bridge: DeviceBridge,
    payload: Data,
    generation: UInt64,
    attempts: Int,
    automatic: Bool
  ) async {
    for attempt in 0..<attempts {
      guard !Task.isCancelled, isCurrentBinding(generation, bridge: bridge) else { return }
      if attempt > 0 {
        await bridge.disconnect()
        guard !Task.isCancelled, isCurrentBinding(generation, bridge: bridge) else { return }
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          return
        }
      }
      do {
        try Task.checkCancellation()
        guard isCurrentBinding(generation, bridge: bridge) else { return }
        devicePhase = .connecting
        try await bridge.connect()
        try Task.checkCancellation()
        guard isCurrentBinding(generation, bridge: bridge) else { return }
        devicePhase = await bridge.phase
        switch devicePhase {
        case .connected, .synced:
          break
        default:
          continue
        }
        devicePhase = .syncing
        try await bridge.sync(payload, now: now())
        try Task.checkCancellation()
        guard isCurrentBinding(generation, bridge: bridge) else { return }
        devicePhase = await bridge.phase
        record(automatic ? "Automatically synced Codex quota" : "Synced Codex quota to StopWatch")
        return
      } catch is CancellationError {
        return
      } catch {
        guard isCurrentBinding(generation, bridge: bridge) else { return }
        devicePhase = await bridge.phase
        if attempt + 1 < attempts {
          record("Retrying StopWatch sync")
        }
      }
    }
    if !Task.isCancelled, isCurrentBinding(generation, bridge: bridge) {
      record("StopWatch sync failed")
    }
  }

  private func ensureBridgeObservation() async {
    guard bridgeEventTask == nil, let bridge else { return }
    await bridge.startObservingTransport()
    let generation = bindingGeneration
    bridgeEventTask = Task { @MainActor [weak self] in
      for await phase in bridge.phaseEvents() {
        guard !Task.isCancelled, let self else { return }
        guard self.isCurrentBinding(generation, bridge: bridge) else { return }
        let wasEstablished: Bool
        switch self.devicePhase {
        case .connected, .syncing, .synced:
          wasEstablished = true
        default:
          wasEstablished = false
        }
        self.devicePhase = phase
        if phase == .disconnected, wasEstablished {
          self.record("StopWatch disconnected")
        }
      }
    }
  }

  private func cancelActiveWatchSync() async {
    guard let active = watchSyncTask, let token = watchSyncToken else { return }
    active.cancel()
    await active.value
    if watchSyncToken == token {
      watchSyncTask = nil
      watchSyncToken = nil
    }
  }

  private func isCurrentBinding(_ generation: UInt64, bridge expectedBridge: DeviceBridge) -> Bool {
    !isChangingBinding
      && generation == bindingGeneration
      && bridge === expectedBridge
      && configuration.boundDeviceIdentifier != nil
  }

  private func record(_ message: String) {
    events.insert(AppEvent(date: now(), message: message), at: 0)
    if events.count > 30 { events.removeLast(events.count - 30) }
  }

  private func observeWake() {
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        await self?.requestRefresh(reason: "Wake refresh")
      }
    }
  }

  private func observeNetwork() {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let available = path.status == .satisfied
      Task { @MainActor in
        self?.handleNetworkState(available)
      }
    }
    monitor.start(
      queue: DispatchQueue(
        label: "io.github.phantom5125.tokenlink.network"))
    pathMonitor = monitor
  }

  private func handleNetworkState(_ available: Bool) {
    if hasSeenNetworkState, available, !networkWasAvailable {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(Int.random(in: 200...1_500)))
        await self?.requestRefresh(reason: "Network restored")
      }
    }
    hasSeenNetworkState = true
    networkWasAvailable = available
  }

  public static func displayName(for provider: ProviderID) -> String {
    ProviderRegistry.displayName(for: provider)
  }

  nonisolated private static func resolveCodexExecutable(configuredPath: String?) -> URL {
    if let configuredPath, FileManager.default.isExecutableFile(atPath: configuredPath) {
      return URL(filePath: configuredPath)
    }
    let pathEntries =
      ProcessInfo.processInfo.environment["PATH"]?
      .split(separator: ":")
      .map(String.init) ?? []
    let candidates =
      pathEntries.map { "\($0)/codex" } + [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        FileManager.default.homeDirectoryForCurrentUser
          .appending(path: ".local/bin/codex").path,
      ]
    if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
      return URL(filePath: path)
    }
    return URL(filePath: "/usr/local/bin/codex")
  }
}
