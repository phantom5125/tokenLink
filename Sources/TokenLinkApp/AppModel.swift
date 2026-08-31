import AppKit
import Foundation
import Network
import OSLog
import Observation
import TokenLinkCore
import TokenLinkDevice
import TokenLinkProviders

private let tokenLinkEventLogger = Logger(
  subsystem: "app.tokenlink",
  category: "events")

private struct ClaudeCredentialGate: CredentialReader {
  let base: any CredentialReader
  let allowsKeychainCredential: Bool

  func apiKey(forAccount account: String) async throws -> String? {
    try await base.apiKey(forAccount: account)
  }

  func cliAccessToken(for provider: ProviderID) async throws -> String? {
    guard provider != .claude || allowsKeychainCredential else { return nil }
    return try await base.cliAccessToken(for: provider)
  }

  func environmentAPIKey(for provider: ProviderID) async throws -> String? {
    try await base.environmentAPIKey(for: provider)
  }
}

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
  /// Beta: locally observed token usage per provider (empty unless enabled).
  public private(set) var localUsageSummaries: [LocalUsageSummary] = []
  public private(set) var isScanningLocalUsage = false
  public private(set) var isAuthorizingClaudeCredential = false
  public private(set) var isMigratingLegacyCredentials = false
  public private(set) var bluetoothDiagnostics = BluetoothDiagnosticSnapshot()
  public private(set) var lastWatchSyncFailure: String?
  public private(set) var lastWatchSyncFailureAt: Date?
  public private(set) var lastWatchFocusOutcome: WatchFocusOutcome?
  public private(set) var lastWatchFocusAt: Date?
  public private(set) var costDashboard: CostDashboardModel

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
  @ObservationIgnored private let localUsageObserver: LocalUsageObserver?
  @ObservationIgnored private let costDashboardBuilder: ((AppConfiguration) -> CostDashboardModel)?
  @ObservationIgnored private let workItemStore: WorkItemStore
  @ObservationIgnored private let codexWorkItemTracker: CodexWorkItemTracker?
  @ObservationIgnored private let codexDesktopActivator: any CodexDesktopActivating
  @ObservationIgnored private let sessionPollInterval: Duration
  @ObservationIgnored private var watchCommandTask: Task<Void, Never>?
  @ObservationIgnored private var sessionPollTask: Task<Void, Never>?
  @ObservationIgnored private var isPollingWorkItems = false
  /// Current watch work items (cache of the actor store for UI binding).
  public private(set) var workItems: [WorkItem] = []
  /// Last payload actually sent to the watch (already redacted by design).
  public private(set) var lastWatchPayloadSummary: String?
  /// Protocol negotiated with the currently connected watch.
  public private(set) var negotiatedWatchProtocol: NegotiatedProtocol?
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
    notificationManager: (any NotificationManaging)? = nil,
    localUsageObserver: LocalUsageObserver? = nil,
    costDashboard: CostDashboardModel? = nil,
    costDashboardBuilder: ((AppConfiguration) -> CostDashboardModel)? = nil,
    workItemStore: WorkItemStore = WorkItemStore(),
    codexWorkItemTracker: CodexWorkItemTracker? = nil,
    codexDesktopActivator: any CodexDesktopActivating = SystemCodexDesktopActivator(),
    sessionPollInterval: Duration = .seconds(10)
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
    self.localUsageObserver = localUsageObserver
    self.costDashboard =
      costDashboard
      ?? CostDashboardModel(
        enabled: configuration.betaCostsEnabled,
        authoritativeSources: [],
        estimateProviders: [],
        authoritativeLoader: { _ in
          .failure(.configuration("No authoritative cost source is configured."))
        },
        estimateLoader: { _ in
          .failure(.configuration("No local cost source is configured."))
        })
    self.costDashboardBuilder = costDashboardBuilder
    self.workItemStore = workItemStore
    self.codexWorkItemTracker = codexWorkItemTracker
    self.codexDesktopActivator = codexDesktopActivator
    self.sessionPollInterval = sessionPollInterval
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
    let localUsageObserver = LocalUsageObserver()
    let catalog = try? PriceCatalog.bundled()
    let makeCoordinator: @Sendable (AppConfiguration) -> RefreshCoordinator = { configuration in
      RefreshCoordinator(
        providers: makeProviders(configuration: configuration, http: http, vault: vault),
        store: store)
    }
    let makeCostDashboard: (AppConfiguration) -> CostDashboardModel = { configuration in
      Self.makeCostDashboard(
        configuration: configuration,
        http: http,
        vault: vault,
        observer: localUsageObserver,
        catalog: catalog)
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
        ? SystemNotificationManager() : NullNotificationManager(),
      localUsageObserver: localUsageObserver,
      costDashboard: makeCostDashboard(configuration),
      costDashboardBuilder: makeCostDashboard,
      codexWorkItemTracker: CodexWorkItemTracker(
        executable: CodexExecutableResolver.resolve(configuredPath: configuration.codexPath),
        transport: ProcessAppServerTransport(
          extraEnvironment: SystemProxyEnvironment.current())))
  }

  nonisolated private static func makeProviders(
    configuration: AppConfiguration,
    http: any HTTPClient,
    vault: any CredentialReader
  ) -> [AccountProvider] {
    var providers: [AccountProvider] = []
    for account in quotaAccounts(in: configuration) {
      let isDefault = configuration.isDefaultAccount(account)
      // Codex and Claude rely on local CLI sign-ins and stay single-instance.
      if account.provider == .codex || account.provider == .claude, !isDefault { continue }
      let provider: any QuotaProvider
      switch account.provider {
      case .codex:
        provider = CodexProvider(
          executable: CodexExecutableResolver.resolve(
            configuredPath: configuration.codexPath),
          transport: ProcessAppServerTransport(
            extraEnvironment: SystemProxyEnvironment.current()))
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
          credentials: account.provider == .claude
            ? ClaudeCredentialGate(
              base: vault,
              allowsKeychainCredential: configuration.claudeCredentialAccessAuthorized)
            : vault)
      case .openrouter, .deepseek:
        continue
      }
      providers.append(AccountProvider(accountID: account.id, provider: provider))
    }
    return providers
  }

  nonisolated static func quotaAccounts(
    in configuration: AppConfiguration
  ) -> [ProviderAccount] {
    configuration.accounts.filter {
      $0.enabled && ProviderRegistry.capabilities(for: $0.provider).contains(.quota)
    }
  }

  private static func makeCostDashboard(
    configuration: AppConfiguration,
    http: any HTTPClient,
    vault: KeychainVault,
    observer: LocalUsageObserver,
    catalog: PriceCatalog?
  ) -> CostDashboardModel {
    var providers: [AccountCostProvider] = []
    for account in configuration.accounts where account.enabled {
      guard ProviderRegistry.capabilities(for: account.provider).contains(.authoritativeCost)
      else { continue }
      let credentialAccount = KeychainVault.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: configuration.isDefaultAccount(account))
      let provider: any AuthoritativeCostProvider
      switch account.provider {
      case .openrouter:
        provider = OpenRouterCostProvider(
          credentialAccount: credentialAccount,
          http: http,
          credentials: vault)
      case .deepseek:
        provider = DeepSeekCostProvider(
          credentialAccount: credentialAccount,
          http: http,
          credentials: vault)
      default:
        continue
      }
      providers.append(AccountCostProvider(accountID: account.id, provider: provider))
    }
    let sources = providers.map {
      AuthoritativeCostSource(accountID: $0.accountID, provider: $0.provider.id)
    }
    let costProviders = providers
    let estimateProviders = ProviderRegistry.localCostEstimateProviderIDs
    let estimator = catalog.map {
      LocalCostEstimator(observer: observer, catalog: $0)
    }
    return CostDashboardModel(
      enabled: configuration.betaCostsEnabled,
      selectedPeriod: configuration.costDisplayPeriod,
      authoritativeSources: sources,
      estimateProviders: estimateProviders,
      authoritativeLoader: { source in
        guard let entry = costProviders.first(where: { $0.accountID == source.accountID }) else {
          return .failure(.configuration("Cost provider configuration is unavailable."))
        }
        return await entry.provider.fetch()
      },
      periodEstimateLoader: { provider in
        guard let estimator else {
          return .failure(.configuration("The bundled price catalog is unavailable."))
        }
        let task = Task.detached(priority: .utility) {
          () -> Result<EstimatedCostPeriodCollection, ProviderFailure> in
          do {
            try Task.checkCancellation()
            let through = Date()
            return .success(
              try estimator.estimatePeriods(
                provider: provider,
                through: through))
          } catch is CancellationError {
            return .failure(.timeout("Local cost scan was cancelled."))
          } catch {
            return .failure(
              .init(kind: .localRead, message: "Local usage could not be read."))
          }
        }
        return await withTaskCancellationHandler {
          await task.value
        } onCancel: {
          task.cancel()
        }
      })
  }

  /// Enabled accounts grouped by provider, in `ProviderID.allCases` order.
  public var accountGroups: [ProviderAccountGroup] {
    ProviderRegistry.quotaProviderIDs.compactMap { provider in
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

  public var costAccountGroups: [ProviderAccountGroup] {
    ProviderRegistry.authoritativeCostProviderIDs.compactMap { provider in
      let rows =
        configuration.accounts
        .filter { $0.provider == provider && $0.enabled }
        .map { account in
          AccountRow(
            id: account.id,
            provider: provider,
            label: account.label,
            isDefault: configuration.isDefaultAccount(account),
            state: ProviderState(phase: .disabled))
        }
      guard !rows.isEmpty else { return nil }
      return ProviderAccountGroup(
        provider: provider,
        displayName: Self.displayName(for: provider),
        accounts: rows)
    }
  }

  public var watchEligibleProviders: [ProviderID] {
    ProviderRegistry.quotaProviderIDs.filter { provider in
      configuration.defaultAccount(for: provider)?.enabled == true
    }
  }

  public var enabledWatchProviders: [ProviderID] {
    watchEligibleProviders.filter { provider in
      configuration.watchSettings.syncedProviders.contains(provider)
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
    let quota =
      "\(Self.displayName(for: highlight.provider)) \(Int(highlight.window.remainingPercent.rounded()))%"
    guard configuration.betaCostsEnabled, let supplement = menuBarCostSupplement else {
      return quota
    }
    return "\(quota) · \(supplement)"
  }

  public var menuBarAccessibilityLabel: String {
    guard let highlight else { return "TokenLink" }
    let quota = String(
      format: text(.menubarQuotaAccessibilityFormat),
      Self.displayName(for: highlight.provider),
      Int(highlight.window.remainingPercent.rounded()))
    guard configuration.betaCostsEnabled else { return quota }
    switch configuration.menuBarCostMetric {
    case .none:
      return quota
    case .localEstimate(let provider):
      guard let row = costDashboard.estimateRows.first(where: { $0.provider == provider }),
        Self.canPresentCost(row.state.phase),
        let totals = row.state.snapshot?.totals,
        totals.count == 1,
        let amount = totals.first
      else { return quota }
      return String(
        format: text(.menubarEstimateAccessibilityFormat),
        quota,
        Self.displayName(for: row.provider),
        CostFormatting.amount(amount, language: currentLanguage),
        costDisplayPeriodAccessibilityText(configuration.costDisplayPeriod),
        costFreshness(row.state.phase))
    case .authoritativeBalance(let accountID, let currency):
      guard
        let row = costDashboard.authoritativeRows.first(where: { $0.id == accountID }),
        Self.canPresentCost(row.state.phase),
        let balance = row.state.snapshot?.balances.first(where: {
          $0.available.currency.caseInsensitiveCompare(currency) == .orderedSame
        })
      else { return quota }
      return String(
        format: text(.menubarBalanceAccessibilityFormat),
        quota,
        Self.displayName(for: row.source.provider),
        CostFormatting.amount(balance.available, language: currentLanguage),
        costFreshness(row.state.phase))
    }
  }

  private var menuBarCostSupplement: String? {
    switch configuration.menuBarCostMetric {
    case .none:
      return nil
    case .localEstimate(let provider):
      guard let row = costDashboard.estimateRows.first(where: { $0.provider == provider }),
        Self.canPresentCost(row.state.phase),
        let totals = row.state.snapshot?.totals,
        totals.count == 1,
        let amount = totals.first
      else { return nil }
      return String(
        format: text(.menubarEstimateCompactFormat),
        CostFormatting.amount(amount, language: currentLanguage),
        costDisplayPeriodCompactText(configuration.costDisplayPeriod))
    case .authoritativeBalance(let accountID, let currency):
      guard
        let row = costDashboard.authoritativeRows.first(where: { $0.id == accountID }),
        Self.canPresentCost(row.state.phase),
        let balance = row.state.snapshot?.balances.first(where: {
          $0.available.currency.caseInsensitiveCompare(currency) == .orderedSame
        })
      else { return nil }
      return String(
        format: text(.menubarBalanceCompactFormat),
        CostFormatting.abbreviation(for: row.source.provider),
        CostFormatting.amount(balance.available, language: currentLanguage))
    }
  }

  private static func canPresentCost(_ phase: ProviderPhase) -> Bool {
    phase == .healthy || phase == .stale || phase == .refreshing
  }

  private func costFreshness(_ phase: ProviderPhase) -> String {
    switch phase {
    case .healthy:
      text(.menubarCostFresh)
    case .stale:
      text(.menubarCostStale)
    case .refreshing:
      text(.menubarCostRefreshing)
    case .disabled, .missingCredential, .error:
      text(.phaseError)
    }
  }

  public func costDisplayPeriodText(_ period: CostDisplayPeriod) -> String {
    switch period {
    case .today: text(.costsPeriodToday)
    case .week: text(.costsPeriodWeek)
    case .month: text(.costsPeriodMonth)
    }
  }

  private func costDisplayPeriodAccessibilityText(_ period: CostDisplayPeriod) -> String {
    switch (currentLanguage, period) {
    case (.english, .today): "today"
    case (.english, .week): "the last 7 days"
    case (.english, .month): "the last 30 days"
    case (.simplifiedChinese, .today): "今天"
    case (.simplifiedChinese, .week): "近 7 天"
    case (.simplifiedChinese, .month): "近 30 天"
    case (.japanese, .today): "今日"
    case (.japanese, .week): "直近7日間"
    case (.japanese, .month): "直近30日間"
    }
  }

  private func costDisplayPeriodCompactText(_ period: CostDisplayPeriod) -> String {
    switch (currentLanguage, period) {
    case (.english, .today): "today"
    case (.english, .week): "7d"
    case (.english, .month): "30d"
    case (.simplifiedChinese, .today): "今天"
    case (.simplifiedChinese, .week): "7天"
    case (.simplifiedChinese, .month): "30天"
    case (.japanese, .today): "今日"
    case (.japanese, .week): "7日"
    case (.japanese, .month): "30日"
    }
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
    record("Starting")
    await ensureBridgeObservation()
    await refreshBluetoothDiagnostics()
    await requestRefresh(reason: "Started")
    await refreshCredentialStates()
    scheduler.start { [weak self] in
      await self?.requestRefresh(reason: "Scheduled refresh")
    }
    startSessionPolling()
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
    watchCommandTask?.cancel()
    watchCommandTask = nil
    sessionPollTask?.cancel()
    sessionPollTask = nil
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
    _ = await refreshCodexWorkItems(
      reason: "Quota refresh", syncWatchOnChange: false)
    if bridge != nil, hasWatchSyncCandidate(allowStale: false) {
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
    if ProviderRegistry.capabilities(for: provider).contains(.quota) {
      rebuildRefresher(reason: "Account added; refreshing")
    } else {
      rebuildCostDashboard()
    }
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
    if ProviderRegistry.capabilities(for: account.provider).contains(.quota) {
      rebuildRefresher(reason: "Account removed; refreshing")
    } else {
      rebuildCostDashboard()
    }
    await refreshCredentialStates()
    record("Removed \(Self.displayName(for: account.provider)) account")
  }

  public func refreshCredentialStates() async {
    guard let vault else { return }
    var byAccount: [UUID: Bool] = [:]
    var sources: [UUID: CredentialSource] = [:]
    for account in configuration.accounts
    where account.enabled && account.provider != .codex {
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
        let mayReadCLI =
          account.provider != .claude || configuration.claudeCredentialAccessAuthorized
        if mayReadCLI {
          let token = (try? await vault.cliAccessToken(for: account.provider)) ?? nil
          if let token, !token.isEmpty {
            byAccount[account.id] = true
            sources[account.id] = .cliCredential
            continue
          }
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
      lastWatchSyncFailure = nil
      lastWatchSyncFailureAt = nil
      record("Bluetooth discovery completed")
    } catch {
      devicePhase = .disconnected
      lastWatchSyncFailure = Self.watchSyncFailureName(error)
      lastWatchSyncFailureAt = now()
      record("Bluetooth discovery failed: \(Self.watchSyncFailureName(error))")
    }
    isDiscovering = false
    await refreshBluetoothDiagnostics()
  }

  public func refreshBluetoothDiagnostics() async {
    guard let bluetoothTransport else {
      bluetoothDiagnostics = BluetoothDiagnosticSnapshot()
      return
    }
    bluetoothDiagnostics = await bluetoothTransport.diagnosticSnapshot()
  }

  public func bindDevice(_ identifier: UUID) async throws {
    guard let bluetoothTransport, !isChangingBinding else { return }
    isChangingBinding = true
    do {
      bindingGeneration &+= 1
      let previousBridge = bridge
      await cancelActiveWatchSync()
      bridgeEventTask?.cancel()
      bridgeEventTask = nil
      watchCommandTask?.cancel()
      watchCommandTask = nil
      await previousBridge?.stopObservingTransport()
      await previousBridge?.disconnect()
      configuration.boundDeviceIdentifier = identifier
      configuration.requiresBluetoothRebinding = false
      bridge = DeviceBridge(
        transport: bluetoothTransport,
        boundIdentifier: identifier)
      devicePhase = .disconnected
      try saveConfiguration()
      await ensureBridgeObservation()
      await refreshBluetoothDiagnostics()
      discoveredDeviceIdentifiers = []
      record("Bound StopWatch; connecting")
    } catch {
      isChangingBinding = false
      throw error
    }
    isChangingBinding = false
    // Binding is an end-to-end action: connect immediately instead of showing
    // a persisted UUID while waiting for an unrelated refresh to prove it.
    await syncCodexNow()
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
    watchCommandTask?.cancel()
    watchCommandTask = nil
    await previousBridge?.stopObservingTransport()
    await previousBridge?.disconnect()
    bridge = nil
    configuration.boundDeviceIdentifier = nil
    configuration.requiresBluetoothRebinding = false
    devicePhase = .unbound
    try saveConfiguration()
    await refreshBluetoothDiagnostics()
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
    let capabilities = ProviderRegistry.capabilities(for: provider)
    try saveConfiguration()
    if provider == .claude {
      rebuildRefresher(reason: "Claude provider setting applied")
    } else if capabilities.contains(.quota) {
      configurationRestartRequired = true
    }
    if capabilities.contains(.authoritativeCost) {
      rebuildCostDashboard()
    }
  }

  /// The only path that may initiate access to Claude Code's Keychain item.
  /// Enabling the provider or launching TokenLink never calls this implicitly.
  public func authorizeClaudeCredentialAccess() async throws {
    guard !isAuthorizingClaudeCredential else { return }
    guard configuration.enabledProviders.contains(.claude) else {
      throw ProviderFailure.configuration(text(.providersClaudeEnableFirst))
    }
    guard let vault else {
      throw ProviderFailure.configuration(text(.providersClaudeCredentialUnavailable))
    }

    isAuthorizingClaudeCredential = true
    defer { isAuthorizingClaudeCredential = false }
    let token: String?
    do {
      token = try await vault.cliAccessToken(for: .claude)
    } catch {
      throw ProviderFailure.configuration(text(.providersClaudeAuthorizationDenied))
    }
    guard let token, !token.isEmpty else {
      throw ProviderFailure.configuration(text(.providersClaudeCredentialUnavailable))
    }

    configuration.claudeCredentialAccessAuthorized = true
    try saveConfiguration()
    if let refresherBuilder { refresher = refresherBuilder(configuration) }
    await refreshCredentialStates()
    await requestRefresh(reason: "Claude Code credential authorized")
    record("Authorized Claude Code credential access")
  }

  /// Stops all future reads of Claude Code's Keychain item. macOS owns the
  /// item's ACL; users can separately remove TokenLink there to revoke the OS
  /// permission itself.
  public func stopUsingClaudeCredential() async throws {
    configuration.claudeCredentialAccessAuthorized = false
    try saveConfiguration()
    await vault?.clearClaudeAccessTokenCache()
    if let refresherBuilder { refresher = refresherBuilder(configuration) }
    await refreshCredentialStates()
    record("Stopped using Claude Code credential")
  }

  /// Explicitly copies TokenLink-owned provider keys from the pre-0.2.1
  /// service. Automatic refresh and launch paths never access that service.
  @discardableResult
  public func migrateLegacyCredentials() async throws -> Int {
    guard !isMigratingLegacyCredentials else { return 0 }
    guard let vault else {
      throw ProviderFailure.configuration("Keychain is unavailable.")
    }

    isMigratingLegacyCredentials = true
    defer { isMigratingLegacyCredentials = false }
    let accounts = configuration.accounts.compactMap { account -> String? in
      guard account.provider != .codex, account.provider != .claude else { return nil }
      return KeychainVault.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: configuration.isDefaultAccount(account))
    }
    let migrated = try await vault.migrateLegacyAPIKeys(forAccounts: accounts)
    configuration.legacyKeychainMigrationCompleted = true
    try saveConfiguration()
    await refreshCredentialStates()
    await requestRefresh(reason: "Legacy TokenLink credentials migrated")
    record("Migrated legacy TokenLink credentials: \(migrated)")
    return migrated
  }

  /// Dismisses the upgrade-only migration offer without touching the legacy
  /// Keychain service. Users can paste fresh keys into TokenLink instead.
  public func dismissLegacyCredentialMigration() throws {
    configuration.legacyKeychainMigrationCompleted = true
    try saveConfiguration()
    record("Dismissed legacy TokenLink credential migration")
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

  public func renameWorkItem(id: String, to name: String) async {
    await workItemStore.rename(id: id, to: name)
    workItems = await workItemStore.items
    await syncCodex(allowStale: true, attempts: 2, automatic: false)
  }

  /// Uses the exact same path as a watch focus command, making the task link
  /// testable from the Mac before relying on BLE and C04 delivery.
  public func focusWorkItemOnMac(slot: Int) async {
    let outcome = await makeFocusHandler().handle(.focus(slot: slot))
    applyFocusOutcome(outcome)
    await reconcileFocusedWorkItem(slot: slot, outcome: outcome)
  }

  public func setWatchSyncedProvider(_ provider: ProviderID, enabled: Bool) throws {
    guard ProviderRegistry.capabilities(for: provider).contains(.quota) else {
      throw ProviderFailure.configuration("Only quota providers can sync to StopWatch.")
    }
    if enabled {
      configuration.watchSettings.syncedProviders.insert(provider)
    } else {
      configuration.watchSettings.syncedProviders.remove(provider)
    }
    try saveConfiguration()
    scheduleWatchSettingsSync()
  }

  public func setWatchFace(_ faceID: WatchFaceID) throws {
    configuration.watchSettings.faceID = faceID
    try saveConfiguration()
    scheduleWatchSettingsSync()
  }

  public func setWatchWakeMode(_ mode: WatchWakeMode) throws {
    configuration.watchSettings.wakeMode = mode
    try saveConfiguration()
    scheduleWatchSettingsSync()
  }

  public func setWatchHourFormat(_ format: WatchHourFormat) throws {
    configuration.watchSettings.hourFormat = format
    try saveConfiguration()
    scheduleWatchSettingsSync()
  }

  public func setNotificationsEnabled(_ enabled: Bool) throws {
    configuration.notificationsEnabled = enabled
    try saveConfiguration()
  }

  public func setFairPaceEnabled(_ enabled: Bool) throws {
    configuration.fairPaceEnabled = enabled
    try saveConfiguration()
  }

  public func setBetaLocalUsageEnabled(_ enabled: Bool) throws {
    configuration.betaLocalUsageEnabled = enabled
    try saveConfiguration()
    if enabled {
      Task { await scanLocalUsage() }
    } else {
      localUsageSummaries = []
    }
  }

  public func setBetaCostsEnabled(_ enabled: Bool) async throws {
    let previousConfiguration = configuration
    configuration.betaCostsEnabled = enabled
    if enabled, configuration.menuBarCostMetric == .none {
      configuration.menuBarCostMetric = .localEstimate(.codex)
    } else if !enabled {
      configuration.menuBarCostMetric = .none
    }

    if enabled {
      do {
        try saveConfiguration()
      } catch {
        configuration = previousConfiguration
        throw error
      }
      await costDashboard.setEnabled(true)
    } else {
      do {
        try saveConfiguration()
      } catch {
        configuration = previousConfiguration
        throw error
      }
      await costDashboard.disable()
    }
  }

  public func setMenuBarCostMetric(_ metric: MenuBarCostMetric) throws {
    guard configuration.betaCostsEnabled || metric == .none else {
      throw ProviderFailure.configuration("Enable Costs beta before selecting a cost metric.")
    }
    configuration.menuBarCostMetric = metric
    try saveConfiguration()
  }

  public func setCostDisplayPeriod(_ period: CostDisplayPeriod) async throws {
    guard configuration.costDisplayPeriod != period else { return }
    let previous = configuration.costDisplayPeriod
    configuration.costDisplayPeriod = period
    do {
      try saveConfiguration()
    } catch {
      configuration.costDisplayPeriod = previous
      throw error
    }
    await costDashboard.setDisplayPeriod(period)
  }

  public func loadCostsIfNeeded() async {
    guard configuration.betaCostsEnabled else { return }
    await costDashboard.loadIfNeeded()
  }

  public func refreshCosts(force: Bool) async {
    guard configuration.betaCostsEnabled else { return }
    await costDashboard.refreshCosts(force: force)
  }

  /// Beta: scans local CLI transcripts (last 7 days) on a background task.
  public func scanLocalUsage() async {
    guard configuration.betaLocalUsageEnabled, let localUsageObserver,
      !isScanningLocalUsage
    else { return }
    isScanningLocalUsage = true
    let since = now().addingTimeInterval(-7 * 86_400)
    localUsageSummaries = await Task.detached {
      localUsageObserver.summarizeAll(since: since)
    }.value
    isScanningLocalUsage = false
    record("Scanned local usage")
  }

  public func diagnosticObject() -> [String: Any] {
    let costMetadata = costDashboard.diagnosticMetadata
    let lastCostRefresh: Any =
      if let value = costMetadata.lastRefreshAt {
        ISO8601DateFormatter().string(from: value)
      } else {
        NSNull()
      }
    let costSources: [[String: Any]] = costMetadata.sources.map { source in
      let errorKind: Any =
        if let value = source.errorKind?.rawValue { value } else { NSNull() }
      let updatedAt: Any =
        if let value = source.updatedAt {
          ISO8601DateFormatter().string(from: value)
        } else {
          NSNull()
        }
      let catalogVersion: Any =
        if let value = source.catalogVersion { value } else { NSNull() }
      return [
        "provider": source.provider.rawValue,
        "kind": source.kind.rawValue,
        "phase": source.phase.rawValue,
        "error_kind": errorKind,
        "updated_at": updatedAt,
        "catalog_version": catalogVersion,
      ]
    }
    return [
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
      "costs": [
        "enabled": configuration.betaCostsEnabled,
        "is_refreshing": costMetadata.isRefreshing,
        "last_refresh_at": lastCostRefresh,
        "sources": costSources,
      ] as [String: Any],
      "device_phase": deviceStatusText,
      "bluetooth": [
        "authorization": bluetoothDiagnostics.authorization.rawValue,
        "central_state": bluetoothDiagnostics.centralState.rawValue,
        "connection_step": bluetoothDiagnostics.connectionStep.rawValue,
        "connected_to_bound_device":
          bluetoothDiagnostics.connectedIdentifier != nil
          && bluetoothDiagnostics.connectedIdentifier == configuration.boundDeviceIdentifier,
        "quota_characteristic": bluetoothDiagnostics.quotaCharacteristicAvailable,
        "capabilities_characteristic":
          bluetoothDiagnostics.capabilitiesCharacteristicAvailable,
        "command_characteristic": bluetoothDiagnostics.commandCharacteristicAvailable,
        "command_notifications": bluetoothDiagnostics.commandNotificationsActive,
        "last_failure": lastWatchSyncFailure ?? "none",
        "last_failure_at": lastWatchSyncFailureAt.map {
          ISO8601DateFormatter().string(from: $0)
        } ?? "none",
      ],
      "events": events.map { ["date": $0.date.timeIntervalSince1970, "message": $0.message] },
    ]
  }

  public func exportDiagnostics(to url: URL) throws {
    try DiagnosticExporter.write(
      diagnosticObject(),
      to: url,
      accountLabels: Set(configuration.accounts.map(\.label)))
  }

  private func saveConfiguration() throws {
    try configurationStore?.save(configuration)
  }

  private func scheduleWatchSettingsSync() {
    guard bridge != nil, hasWatchSyncCandidate(allowStale: true) else { return }
    Task { @MainActor [weak self] in
      await self?.syncCodex(allowStale: true, attempts: 2, automatic: false)
    }
  }

  private func hasWatchSyncCandidate(allowStale: Bool) -> Bool {
    enabledWatchProviders.contains { provider in
      guard let account = configuration.defaultAccount(for: provider), account.enabled,
        let state = states[account.id]
      else { return false }
      return state.phase == .healthy || (allowStale && state.phase == .stale)
    }
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
    guard let bridge else { return }

    let generation = bindingGeneration
    let boundedAttempts = min(2, max(1, attempts))
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performWatchSync(
        bridge: bridge,
        generation: generation,
        attempts: boundedAttempts,
        automatic: automatic,
        allowStale: allowStale)
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

  /// Builds the next watch payload after the connection is up, so the
  /// negotiated protocol reflects this connection. v1 watches only ever
  /// receive the Codex legacy payload.
  private func buildWatchDecisions(
    bridge: DeviceBridge,
    allowStale: Bool
  ) async -> [WatchSyncPolicy.Decision] {
    let negotiated = await bridge.negotiatedProtocol
    var candidates: [(provider: ProviderID, snapshot: QuotaSnapshot)] = []
    for provider in enabledWatchProviders {
      guard let account = configuration.defaultAccount(for: provider),
        account.enabled,
        let state = states[account.id],
        state.phase == .healthy || (allowStale && state.phase == .stale),
        let snapshot = state.snapshot
      else { continue }
      candidates.append((provider, snapshot))
    }
    let items = await workItemStore.payloadItems()
    let activeSessionCount = await workItemStore.activeSessionCount
    let decisions = WatchSyncPolicy.payloads(
      negotiated: negotiated,
      candidates: candidates,
      settings: configuration.watchSettings,
      workItems: items,
      activeSessionCount: activeSessionCount,
      now: now())
    guard !decisions.isEmpty else { return [] }
    negotiatedWatchProtocol = negotiated
    switch negotiated {
    case .v1:
      record("Negotiated StopWatch protocol v1")
    case .v2:
      record("Negotiated StopWatch protocol v2; sending \(decisions.count) providers")
    }
    lastWatchPayloadSummary =
      decisions
      .map { String(decoding: $0.data, as: UTF8.self) }
      .joined(separator: "\n")
    return decisions
  }

  private func performWatchSync(
    bridge: DeviceBridge,
    generation: UInt64,
    attempts: Int,
    automatic: Bool,
    allowStale: Bool
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
        let decisions = await buildWatchDecisions(
          bridge: bridge, allowStale: allowStale)
        guard !decisions.isEmpty else { return }
        devicePhase = .syncing
        for decision in decisions {
          try await bridge.sync(decision.data, now: now())
        }
        try Task.checkCancellation()
        guard isCurrentBinding(generation, bridge: bridge) else { return }
        devicePhase = await bridge.phase
        lastWatchSyncFailure = nil
        lastWatchSyncFailureAt = nil
        await refreshBluetoothDiagnostics()
        let names = decisions.map { Self.displayName(for: $0.provider) }
          .joined(separator: ", ")
        record(
          automatic
            ? "Automatically synced \(names) quota"
            : "Synced \(names) quota to StopWatch")
        return
      } catch is CancellationError {
        return
      } catch {
        guard isCurrentBinding(generation, bridge: bridge) else { return }
        devicePhase = await bridge.phase
        let failure = Self.watchSyncFailureName(error)
        lastWatchSyncFailure = failure
        lastWatchSyncFailureAt = now()
        await refreshBluetoothDiagnostics()
        record("StopWatch sync attempt failed: \(failure)")
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
    let focusHandler = makeFocusHandler()
    watchCommandTask = Task { @MainActor [weak self] in
      for await command in bridge.commandStream {
        guard !Task.isCancelled, let self else { return }
        guard self.isCurrentBinding(generation, bridge: bridge) else { return }
        switch command {
        case .focus(let slot):
          self.record("Watch command received: focus slot \(slot)")
        case .refresh:
          self.record("Watch command received: refresh")
        }
        let outcome = await focusHandler.handle(command)
        self.applyFocusOutcome(outcome)
        if case .focus(let slot) = command {
          await self.reconcileFocusedWorkItem(slot: slot, outcome: outcome)
        }
      }
    }
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
        await self.refreshBluetoothDiagnostics()
        if phase == .disconnected, wasEstablished {
          self.record("StopWatch disconnected")
        }
      }
    }
  }

  private func makeFocusHandler() -> FocusHandler {
    let workItemStore = workItemStore
    return FocusHandler(
      sessionProvider: { slot in
        await workItemStore.item(forSlot: slot).map {
          FocusSession(slot: $0.slot, source: $0.source, threadID: $0.id)
        }
      },
      activator: codexDesktopActivator,
      onRefresh: { [weak self] in
        await self?.requestRefresh(reason: "Watch requested refresh")
      },
      record: { [weak self] message in
        await self?.record(message)
      })
  }

  private func applyFocusOutcome(_ outcome: WatchFocusOutcome?) {
    guard let outcome else { return }
    lastWatchFocusOutcome = outcome
    lastWatchFocusAt = now()
  }

  /// Reconciles execution state immediately after a successful task link and
  /// records acknowledgement independently. An item stays needs-input until
  /// Codex reports a real lifecycle transition; opening it only sets `seen`.
  private func reconcileFocusedWorkItem(
    slot: Int,
    outcome: WatchFocusOutcome?
  ) async {
    guard outcome == .openedThread else { return }
    let acknowledged = await workItemStore.acknowledge(slot: slot, at: now())
    let refreshed = await refreshCodexWorkItems(
      reason: "Focused session", syncWatchOnChange: false)
    workItems = await workItemStore.items
    guard acknowledged || refreshed, bridge != nil,
      hasWatchSyncCandidate(allowStale: true)
    else { return }
    await syncCodex(allowStale: true, attempts: 2, automatic: true)
  }

  /// Polls task lifecycle independently of the quota cadence. Successful
  /// changes are the only scheduled polls that write a new watch payload.
  @discardableResult
  private func refreshCodexWorkItems(
    reason: String,
    syncWatchOnChange: Bool
  ) async -> Bool {
    guard !isPollingWorkItems, let codexWorkItemTracker,
      configuration.defaultAccount(for: .codex)?.enabled == true
    else { return false }
    isPollingWorkItems = true
    defer { isPollingWorkItems = false }

    let previousItems = await workItemStore.items
    let previousActiveCount = await workItemStore.activeSessionCount
    if let failure = await codexWorkItemTracker.poll(into: workItemStore) {
      record("Codex work items unavailable: \(failure.kind.rawValue)")
      return false
    }
    let replacementItems = await workItemStore.items
    let activeSessionCount = await workItemStore.activeSessionCount
    workItems = replacementItems
    let changed =
      replacementItems != previousItems
      || activeSessionCount != previousActiveCount
    if changed || reason != "Scheduled session refresh" {
      record(
        "Codex work items available: \(replacementItems.count); active sessions: \(activeSessionCount)"
      )
    }
    if changed, syncWatchOnChange, bridge != nil,
      hasWatchSyncCandidate(allowStale: true)
    {
      await syncCodex(allowStale: true, attempts: 2, automatic: true)
    }
    return changed
  }

  private func startSessionPolling() {
    sessionPollTask?.cancel()
    let interval = sessionPollInterval
    sessionPollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
        guard !Task.isCancelled, let self, self.started else { return }
        await self.refreshCodexWorkItems(
          reason: "Scheduled session refresh", syncWatchOnChange: true)
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
    tokenLinkEventLogger.notice("\(message, privacy: .public)")
    events.insert(AppEvent(date: now(), message: message), at: 0)
    if events.count > 30 { events.removeLast(events.count - 30) }
  }

  private static func watchSyncFailureName(_ error: Error) -> String {
    guard let bluetooth = error as? BluetoothTransportError else {
      return String(describing: type(of: error))
    }
    switch bluetooth {
    case .unavailable: return "bluetooth unavailable"
    case .operationInProgress: return "operation in progress"
    case .timeout: return "timeout"
    case .peripheralNotFound: return "bound device not found"
    case .serviceNotFound: return "quota service not found"
    case .characteristicNotFound: return "quota characteristic not found"
    case .commandNotificationsUnavailable: return "watch command notifications unavailable"
    case .disconnected: return "device disconnected"
    case .system: return "CoreBluetooth system error"
    }
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
        label: "app.tokenlink.network"))
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

  private func rebuildCostDashboard() {
    guard let costDashboardBuilder else { return }
    let previous = costDashboard
    costDashboard = costDashboardBuilder(configuration)
    Task { await previous.disable() }
  }

  public static func displayName(for provider: ProviderID) -> String {
    ProviderRegistry.displayName(for: provider)
  }

}
