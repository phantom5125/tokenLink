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
  public private(set) var states: [ProviderID: ProviderState]
  public private(set) var devicePhase: DevicePhase
  public private(set) var events: [AppEvent] = []
  public private(set) var isRefreshing = false
  public private(set) var isDiscovering = false
  public private(set) var discoveredDeviceIdentifiers: [UUID] = []
  public private(set) var credentialConfigured: [ProviderID: Bool] = [:]
  public private(set) var loginItemState: LoginItemState = .disabled
  public private(set) var configurationRestartRequired = false
  public var configuration: AppConfiguration

  @ObservationIgnored private let refresher: any AppRefreshing
  @ObservationIgnored private let stateLoader:
    @Sendable (TimeInterval) async -> [ProviderID: ProviderState]
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
  @ObservationIgnored private var isChangingBinding = false

  public init(
    refresher: any AppRefreshing,
    now: @escaping @Sendable () -> Date = { Date() },
    stateLoader: @escaping @Sendable (TimeInterval) async -> [ProviderID: ProviderState] = { _ in
      [:]
    },
    configuration: AppConfiguration = .default,
    configurationStore: ConfigurationStore? = nil,
    vault: KeychainVault? = nil,
    bluetoothTransport: (any BLETransport)? = nil,
    loginController: LoginItemController? = nil
  ) {
    self.refresher = refresher
    self.now = now
    self.stateLoader = stateLoader
    self.configuration = configuration
    self.configurationStore = configurationStore
    self.vault = vault
    self.bluetoothTransport = bluetoothTransport
    self.loginController = loginController
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
    model.states = Dictionary(
      uniqueKeysWithValues: snapshots.map {
        ($0.provider, ProviderState(phase: .healthy, snapshot: $0))
      })
    return model
  }

  public static func live() -> AppModel {
    let configurationStore = try? ConfigurationStore.applicationSupport()
    let configuration = (try? configurationStore?.load()) ?? .default
    let vault = KeychainVault()
    let http = URLSessionHTTPClient()
    let store = ProviderStore()
    var providers: [any QuotaProvider] = []

    if configuration.enabledProviders.contains(.codex) {
      providers.append(
        CodexProvider(
          executable: resolveCodexExecutable(
            configuredPath: configuration.codexPath)))
    }
    if configuration.enabledProviders.contains(.kimi) {
      providers.append(KimiProvider(http: http, credentials: vault))
    }
    if configuration.enabledProviders.contains(.minimax) {
      providers.append(
        MiniMaxProvider(
          region: configuration.miniMaxRegion,
          http: http,
          credentials: vault))
    }
    if configuration.enabledProviders.contains(.glm) {
      providers.append(
        GLMProvider(
          region: configuration.glmRegion,
          http: http,
          credentials: vault))
    }

    let coordinator = RefreshCoordinator(providers: providers, store: store)
    return AppModel(
      refresher: coordinator,
      stateLoader: { refreshIntervalSeconds in
        await store.allStates(refreshIntervalSeconds: refreshIntervalSeconds)
      },
      configuration: configuration,
      configurationStore: configurationStore,
      vault: vault,
      bluetoothTransport: CoreBluetoothTransport(),
      loginController: LoginItemController())
  }

  public var orderedProviderRows: [ProviderRow] {
    ProviderID.allCases.compactMap { provider in
      guard configuration.enabledProviders.contains(provider) else { return nil }
      return ProviderRow(
        id: provider,
        displayName: Self.displayName(for: provider),
        state: states[provider] ?? ProviderState(phase: .disabled))
    }
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
    switch devicePhase {
    case .unbound: "Not bound"
    case .disconnected: "Disconnected"
    case .scanning: "Scanning"
    case .connecting: "Connecting"
    case .connected: "Connected"
    case .syncing: "Syncing"
    case .synced: "Synced"
    case .stale: "Sync stale"
    }
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
    states = await stateLoader(TimeInterval(configuration.refreshMinutes * 60))
    if bridge != nil, states[.codex]?.phase == .healthy {
      await syncCodex(allowStale: false, attempts: 2, automatic: true)
    } else if case .synced = devicePhase {
      devicePhase = .stale
    }
    isRefreshing = false
    record(reason)
  }

  public func saveAPIKey(_ value: String, for provider: ProviderID) async throws {
    guard let vault else { return }
    if value.isEmpty {
      try await vault.deleteAPIKey(for: provider)
      credentialConfigured[provider] = false
    } else {
      try await vault.setAPIKey(value, for: provider)
      credentialConfigured[provider] = true
    }
    record("Updated \(Self.displayName(for: provider)) credentials")
  }

  public func deleteAPIKey(for provider: ProviderID) async throws {
    try await saveAPIKey("", for: provider)
  }

  public func refreshCredentialStates() async {
    guard let vault else { return }
    for provider in ProviderID.allCases where provider != .codex {
      let apiKey = (try? await vault.apiKey(for: provider)) ?? nil
      let cliToken = (try? await vault.cliAccessToken(for: provider)) ?? nil
      credentialConfigured[provider] = apiKey != nil || cliToken != nil
    }
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
      configuration.enabledProviders.insert(provider)
    } else {
      configuration.enabledProviders.remove(provider)
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
    configurationRestartRequired = true
    try saveConfiguration()
  }

  public func setGLMRegion(_ region: GLMRegion) throws {
    configuration.glmRegion = region
    configurationRestartRequired = true
    try saveConfiguration()
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
      let state = states[.codex],
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
    switch provider {
    case .codex: "Codex"
    case .kimi: "Kimi"
    case .minimax: "MiniMax"
    case .glm: "GLM"
    }
  }

  private static func resolveCodexExecutable(configuredPath: String?) -> URL {
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
