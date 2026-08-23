import AppKit
import Foundation
import Network
import TokenLinkCore
import TokenLinkDevice
import TokenLinkProviders

/// UI 触发刷新的抽象，测试里用计数 fake 替代真实网络。
public protocol AppRefreshing: Sendable {
  func refresh() async
}

extension RefreshCoordinator: AppRefreshing {
  public func refresh() async { await refreshAll() }
}

@MainActor @Observable
public final class AppModel {
  public struct ProviderRow: Identifiable, Equatable, Sendable {
    public let provider: ProviderID
    public let phase: ProviderPhase
    public let snapshot: QuotaSnapshot?
    public let error: ProviderFailure?
    public var id: ProviderID { provider }
  }

  public struct Highlight: Equatable, Sendable {
    public let provider: ProviderID
    public let window: QuotaWindow
  }

  public private(set) var rows: [ProviderRow] = []
  public private(set) var devicePhase: DevicePhase = .unbound
  public private(set) var events: [String] = []
  public var configuration: AppConfiguration

  private let refresher: (any AppRefreshing)?
  private let store: ProviderStore?
  private let vault: KeychainVault?
  private let configurationStore: ConfigurationStore?
  private var deviceBridge: DeviceBridge?
  private let makeBridge: (@Sendable (UUID?) -> DeviceBridge)?
  private let now: () -> Date
  private var lastManualRefresh: Date?
  private var schedulerTask: Task<Void, Never>?
  private var pathMonitor: NWPathMonitor?

  private static let manualThrottleSeconds: TimeInterval = 10

  public init(refresher: any AppRefreshing, now: @escaping () -> Date = Date.init) {
    self.refresher = refresher
    self.now = now
    self.store = nil
    self.vault = nil
    self.configurationStore = nil
    self.makeBridge = nil
    self.configuration = AppConfiguration()
  }

  private init(
    refresher: (any AppRefreshing)?,
    store: ProviderStore?,
    vault: KeychainVault?,
    configurationStore: ConfigurationStore?,
    configuration: AppConfiguration,
    makeBridge: (@Sendable (UUID?) -> DeviceBridge)?,
    now: @escaping () -> Date
  ) {
    self.refresher = refresher
    self.store = store
    self.vault = vault
    self.configurationStore = configurationStore
    self.configuration = configuration
    self.makeBridge = makeBridge
    self.now = now
    self.deviceBridge = makeBridge?(configuration.boundDeviceIdentifier)
    self.devicePhase = configuration.boundDeviceIdentifier == nil ? .unbound : .disconnected
  }

  /// 预览/测试用模型：不做任何网络与设备访问。
  public static func preview(snapshots: [QuotaSnapshot]) -> AppModel {
    let model = AppModel(
      refresher: nil, store: nil, vault: nil, configurationStore: nil,
      configuration: AppConfiguration(), makeBridge: nil, now: Date.init)
    model.rows = snapshots.map {
      ProviderRow(provider: $0.provider, phase: .healthy, snapshot: $0, error: nil)
    }
    return model
  }

  /// 真实装配：配置目录、Keychain、四个 Provider、刷新协调器与蓝牙桥。
  public static func live() -> AppModel {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    let configurationStore = ConfigurationStore(directory: support.appending(path: "TokenLink"))
    let configuration = configurationStore.load()
    let vault = KeychainVault()
    let http = URLSessionHTTPClient()
    let codexURL =
      configuration.codexPath.map { URL(fileURLWithPath: $0) }
      ?? URL(fileURLWithPath: "/opt/homebrew/bin/codex")
    let providers: [any QuotaProvider] = [
      CodexProvider(executable: codexURL, transport: ProcessAppServerTransport()),
      KimiProvider(http: http, credentials: vault),
      MiniMaxProvider(region: configuration.miniMaxRegion, http: http, credentials: vault),
      GLMProvider(region: configuration.glmRegion, http: http, credentials: vault),
    ]
    let store = ProviderStore()
    let coordinator = RefreshCoordinator(providers: providers, store: store)
    return AppModel(
      refresher: coordinator, store: store, vault: vault,
      configurationStore: configurationStore, configuration: configuration,
      makeBridge: { DeviceBridge(transport: CoreBluetoothTransport(), boundIdentifier: $0) },
      now: Date.init)
  }

  /// 所有行里剩余量最低的健康/可接受陈旧窗口，用于菜单栏高亮。
  public var highlight: Highlight? {
    rows.compactMap { row -> Highlight? in
      guard row.phase == .healthy || row.phase == .stale,
        let snapshot = row.snapshot,
        let window = snapshot.mostConstrainedWindow
      else { return nil }
      return Highlight(provider: row.provider, window: window)
    }.min { $0.window.remainingPercent < $1.window.remainingPercent }
  }

  public var menuBarLabel: String {
    guard let highlight else { return "—" }
    return "\(Int(highlight.window.remainingPercent))%"
  }

  public func refreshManually() async {
    let now = now()
    if let last = lastManualRefresh,
      now.timeIntervalSince(last) < Self.manualThrottleSeconds
    {
      return
    }
    lastManualRefresh = now
    await refresh()
  }

  func refresh() async {
    guard let refresher else { return }
    await refresher.refresh()
    await reloadFromStore()
    record("Refreshed provider quota")
  }

  /// 启动周期刷新；唤醒与网络恢复时触发一次去抖刷新。
  public func start() {
    Task { await refresh() }
    let scheduler = RefreshScheduler(minutes: configuration.refreshMinutes)
    schedulerTask = scheduler.start { [weak self] in await self?.refresh() }
    NotificationCenter.default.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
    ) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.refresh() }
    }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }
      Task { @MainActor [weak self] in await self?.refresh() }
    }
    monitor.start(queue: DispatchQueue(label: "tokenlink.network"))
    pathMonitor = monitor
  }

  private func reloadFromStore() async {
    guard let store else { return }
    let states = await store.allStates()
    rows = ProviderID.allCases.map { id in
      let state = states[id] ?? ProviderState(phase: .disabled)
      return ProviderRow(
        provider: id, phase: state.phase, snapshot: state.snapshot, error: state.error)
    }
  }

  public func saveAPIKey(_ key: String, for provider: ProviderID) async throws {
    guard let vault else { return }
    try vault.setAPIKey(key, for: provider)
    record("Saved API key for \(provider.rawValue)")
  }

  public func deleteAPIKey(for provider: ProviderID) async throws {
    guard let vault else { return }
    try vault.deleteAPIKey(for: provider)
    record("Deleted API key for \(provider.rawValue)")
  }

  public func bindDevice(_ identifier: UUID) {
    configuration.boundDeviceIdentifier = identifier
    try? configurationStore?.save(configuration)
    deviceBridge = makeBridge?(identifier)
    devicePhase = .disconnected
    record("Bound StopWatch \(identifier.uuidString)")
  }

  /// 只把 Codex primary 窗口编码进 v1 协议并写入手表。
  public func syncCodexNow() async {
    guard let store, let bridge = deviceBridge else { return }
    let state = await store.state(for: .codex)
    guard let snapshot = state.snapshot,
      state.phase == .healthy || state.phase == .stale
    else {
      record("No fresh Codex snapshot to sync")
      return
    }
    do {
      try await bridge.connect()
      let data = try LegacyWatchProjection.encode(snapshot: snapshot, now: now())
      try await bridge.sync(data, now: now())
      devicePhase = await bridge.phase
      record("Synced Codex quota to StopWatch")
    } catch {
      devicePhase = await bridge.phase
      record("StopWatch sync failed: \(error.localizedDescription)")
    }
  }

  private func record(_ event: String) {
    events.insert(event, at: 0)
    if events.count > 50 { events.removeLast() }
  }
}
