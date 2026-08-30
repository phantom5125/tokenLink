import Foundation
import TokenLinkCore
import TokenLinkDevice
import TokenLinkProviders

public struct ProviderAccount: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let provider: ProviderID
  public var label: String
  public var enabled: Bool

  public init(
    id: UUID = UUID(),
    provider: ProviderID,
    label: String,
    enabled: Bool = true
  ) {
    self.id = id
    self.provider = provider
    self.label = label
    self.enabled = enabled
  }
}

public enum WatchWakeMode: String, Codable, Sendable {
  case raise
  case tap
}

public enum WatchHourFormat: String, Codable, Sendable {
  case system
  case h12
  case h24
}

/// StopWatch v2 preferences. `syncedProviders` defaults to Codex only, which
/// keeps v1 behavior identical for existing users.
public struct WatchSettings: Codable, Equatable, Sendable {
  public var syncedProviders: Set<ProviderID>
  public var faceID: WatchFaceID
  public var wakeMode: WatchWakeMode
  public var hourFormat: WatchHourFormat

  public init(
    syncedProviders: Set<ProviderID> = [.codex],
    faceID: WatchFaceID = .data,
    wakeMode: WatchWakeMode = .raise,
    hourFormat: WatchHourFormat = .system
  ) {
    self.syncedProviders = syncedProviders
    self.faceID = faceID
    self.wakeMode = wakeMode
    self.hourFormat = hourFormat
  }

  private enum CodingKeys: String, CodingKey {
    case syncedProviders
    case faceID
    case legacyFaceTheme = "faceTheme"
    case wakeMode
    case hourFormat
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawFaceID =
      try container.decodeIfPresent(String.self, forKey: .faceID)
      ?? container.decodeIfPresent(String.self, forKey: .legacyFaceTheme)
    self.init(
      syncedProviders: try container.decodeIfPresent(
        Set<ProviderID>.self, forKey: .syncedProviders) ?? [.codex],
      faceID: rawFaceID.flatMap(WatchFaceID.init(rawValue:)) ?? .data,
      wakeMode: try container.decodeIfPresent(WatchWakeMode.self, forKey: .wakeMode) ?? .raise,
      hourFormat: try container.decodeIfPresent(WatchHourFormat.self, forKey: .hourFormat)
        ?? .system)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(syncedProviders, forKey: .syncedProviders)
    try container.encode(faceID, forKey: .faceID)
    try container.encode(wakeMode, forKey: .wakeMode)
    try container.encode(hourFormat, forKey: .hourFormat)
  }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
  private static let currentBluetoothIdentityVersion = 1

  /// Accounts are the source of truth for provider enablement; ordered, and
  /// the first account of each provider is its default account.
  public var accounts: [ProviderAccount]
  public var refreshMinutes: Int
  public var boundDeviceIdentifier: UUID?
  /// The 0.2.1 bundle-identifier change gives TokenLink a new CoreBluetooth
  /// identity. Peripheral UUIDs saved by the old app cannot be trusted until
  /// the user scans and binds again under `app.tokenlink`.
  public var requiresBluetoothRebinding: Bool
  public var codexPath: String?
  public var miniMaxRegion: MiniMaxRegion
  public var glmRegion: GLMRegion
  /// nil = follow the system language; otherwise an `AppLanguage` raw value.
  public var appLanguage: String?
  /// macOS notifications for low quota, resets, and credential failures.
  public var notificationsEnabled: Bool
  /// Draws the fair-pace reference marker on quota bars (even-consumption
  /// baseline, e.g. 6/7 remaining one day into a weekly window).
  public var fairPaceEnabled: Bool
  /// Beta: aggregate local CLI transcript token usage for cross-checking
  /// provider-reported quota.
  public var betaLocalUsageEnabled: Bool
  /// The user explicitly allowed TokenLink to read Claude Code's Keychain
  /// credential. Provider enablement alone must never trigger that access.
  public var claudeCredentialAccessAuthorized: Bool
  /// Existing installations must explicitly opt into copying provider keys
  /// from TokenLink's pre-0.2.1 Keychain service. Fresh installs have nothing
  /// to migrate and start with this flow completed.
  public var legacyKeychainMigrationCompleted: Bool
  /// Beta: authoritative balances and local API-equivalent cost estimates.
  public var betaCostsEnabled: Bool
  /// Fixed optional supplement displayed after the primary quota label.
  public var menuBarCostMetric: MenuBarCostMetric
  /// Persisted display period shared by the Costs screen and menu-bar estimate.
  public var costDisplayPeriod: CostDisplayPeriod
  /// StopWatch v2 preferences (face, wake, hour format, synced providers).
  public var watchSettings: WatchSettings

  /// Derived from enabled accounts; kept for readable call sites.
  public var enabledProviders: Set<ProviderID> {
    Set(accounts.filter(\.enabled).map(\.provider))
  }

  public init(
    accounts: [ProviderAccount],
    refreshMinutes: Int,
    boundDeviceIdentifier: UUID?,
    requiresBluetoothRebinding: Bool = false,
    codexPath: String?,
    miniMaxRegion: MiniMaxRegion,
    glmRegion: GLMRegion,
    appLanguage: String? = nil,
    notificationsEnabled: Bool = true,
    fairPaceEnabled: Bool = false,
    betaLocalUsageEnabled: Bool = false,
    claudeCredentialAccessAuthorized: Bool = false,
    legacyKeychainMigrationCompleted: Bool = true,
    betaCostsEnabled: Bool = false,
    menuBarCostMetric: MenuBarCostMetric = .none,
    costDisplayPeriod: CostDisplayPeriod = .week,
    watchSettings: WatchSettings = WatchSettings()
  ) {
    self.accounts = accounts
    self.refreshMinutes = min(60, max(1, refreshMinutes))
    self.boundDeviceIdentifier = boundDeviceIdentifier
    self.requiresBluetoothRebinding = requiresBluetoothRebinding
    self.codexPath = codexPath
    self.miniMaxRegion = miniMaxRegion
    self.glmRegion = glmRegion
    self.appLanguage = appLanguage
    self.notificationsEnabled = notificationsEnabled
    self.fairPaceEnabled = fairPaceEnabled
    self.betaLocalUsageEnabled = betaLocalUsageEnabled
    self.claudeCredentialAccessAuthorized = claudeCredentialAccessAuthorized
    self.legacyKeychainMigrationCompleted = legacyKeychainMigrationCompleted
    self.betaCostsEnabled = betaCostsEnabled
    self.menuBarCostMetric = menuBarCostMetric
    self.costDisplayPeriod = costDisplayPeriod
    self.watchSettings = watchSettings
  }

  public init(
    enabledProviders: Set<ProviderID>,
    refreshMinutes: Int,
    boundDeviceIdentifier: UUID?,
    codexPath: String?,
    miniMaxRegion: MiniMaxRegion,
    glmRegion: GLMRegion,
    appLanguage: String? = nil
  ) {
    self.init(
      accounts: Self.defaultAccounts(for: enabledProviders),
      refreshMinutes: refreshMinutes,
      boundDeviceIdentifier: boundDeviceIdentifier,
      codexPath: codexPath,
      miniMaxRegion: miniMaxRegion,
      glmRegion: glmRegion,
      appLanguage: appLanguage)
  }

  public static let `default` = AppConfiguration(
    // Claude is opt-in because enabling it can request access to a credential
    // owned by another app. The other providers use TokenLink-owned keys,
    // documented files, or local processes.
    enabledProviders: Set(ProviderRegistry.quotaProviderIDs).subtracting([.claude]),
    refreshMinutes: 5,
    boundDeviceIdentifier: nil,
    codexPath: nil,
    miniMaxRegion: .global,
    glmRegion: .global)

  public static func defaultAccounts(for providers: Set<ProviderID>) -> [ProviderAccount] {
    ProviderRegistry.quotaProviderIDs.filter(providers.contains).map { provider in
      ProviderAccount(
        provider: provider,
        label: ProviderRegistry.displayName(for: provider))
    }
  }

  public func defaultAccount(for provider: ProviderID) -> ProviderAccount? {
    accounts.first { $0.provider == provider }
  }

  public func isDefaultAccount(_ account: ProviderAccount) -> Bool {
    defaultAccount(for: account.provider)?.id == account.id
  }

  private enum CodingKeys: String, CodingKey {
    case accounts
    case refreshMinutes
    case boundDeviceIdentifier
    case bluetoothIdentityVersion
    case requiresBluetoothRebinding
    case codexPath
    case miniMaxRegion
    case glmRegion
    case appLanguage
    case legacyEnabledProviders = "enabledProviders"
    case notificationsEnabled
    case fairPaceEnabled
    case betaLocalUsageEnabled
    case claudeCredentialAccessAuthorized
    case legacyKeychainMigrationCompleted
    case betaCostsEnabled
    case menuBarCostMetric
    case costDisplayPeriod
    case watchSettings
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let accounts: [ProviderAccount]
    if let decoded = try container.decodeIfPresent(
      [ProviderAccount].self, forKey: .accounts)
    {
      accounts = decoded
    } else if let legacy = try container.decodeIfPresent(
      [ProviderID].self, forKey: .legacyEnabledProviders)
    {
      // Migrate pre-account configs: one default account per enabled provider.
      accounts = Self.defaultAccounts(for: Set(legacy))
    } else {
      accounts = Self.defaultAccounts(
        for: Set(ProviderRegistry.quotaProviderIDs).subtracting([.claude]))
    }
    let decodedBoundDeviceIdentifier = try container.decodeIfPresent(
      UUID.self, forKey: .boundDeviceIdentifier)
    let bluetoothIdentityVersion =
      try container.decodeIfPresent(
        Int.self, forKey: .bluetoothIdentityVersion) ?? 0
    let requiresBluetoothRebinding =
      bluetoothIdentityVersion < Self.currentBluetoothIdentityVersion
      && decodedBoundDeviceIdentifier != nil
    let persistedBluetoothRebinding =
      try container.decodeIfPresent(
        Bool.self, forKey: .requiresBluetoothRebinding) ?? false
    self.init(
      accounts: accounts,
      refreshMinutes: try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5,
      boundDeviceIdentifier: requiresBluetoothRebinding ? nil : decodedBoundDeviceIdentifier,
      requiresBluetoothRebinding: requiresBluetoothRebinding || persistedBluetoothRebinding,
      codexPath: try container.decodeIfPresent(String.self, forKey: .codexPath),
      miniMaxRegion: try container.decodeIfPresent(MiniMaxRegion.self, forKey: .miniMaxRegion)
        ?? .global,
      glmRegion: try container.decodeIfPresent(GLMRegion.self, forKey: .glmRegion) ?? .global,
      appLanguage: try container.decodeIfPresent(String.self, forKey: .appLanguage),
      notificationsEnabled: try container.decodeIfPresent(
        Bool.self, forKey: .notificationsEnabled) ?? true,
      fairPaceEnabled: try container.decodeIfPresent(
        Bool.self, forKey: .fairPaceEnabled) ?? false,
      betaLocalUsageEnabled: try container.decodeIfPresent(
        Bool.self, forKey: .betaLocalUsageEnabled) ?? false,
      claudeCredentialAccessAuthorized: try container.decodeIfPresent(
        Bool.self, forKey: .claudeCredentialAccessAuthorized) ?? false,
      // A saved config without this field predates the explicit migration UI.
      // Do not touch the old Keychain service until the user chooses to migrate.
      legacyKeychainMigrationCompleted: try container.decodeIfPresent(
        Bool.self, forKey: .legacyKeychainMigrationCompleted) ?? false,
      betaCostsEnabled: try container.decodeIfPresent(
        Bool.self, forKey: .betaCostsEnabled) ?? false,
      menuBarCostMetric: try container.decodeIfPresent(
        MenuBarCostMetric.self, forKey: .menuBarCostMetric) ?? .none,
      costDisplayPeriod: try container.decodeIfPresent(
        CostDisplayPeriod.self, forKey: .costDisplayPeriod) ?? .week,
      watchSettings: try container.decodeIfPresent(
        WatchSettings.self, forKey: .watchSettings) ?? WatchSettings())
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(accounts, forKey: .accounts)
    try container.encode(refreshMinutes, forKey: .refreshMinutes)
    try container.encodeIfPresent(boundDeviceIdentifier, forKey: .boundDeviceIdentifier)
    try container.encode(
      Self.currentBluetoothIdentityVersion, forKey: .bluetoothIdentityVersion)
    try container.encode(requiresBluetoothRebinding, forKey: .requiresBluetoothRebinding)
    try container.encodeIfPresent(codexPath, forKey: .codexPath)
    try container.encode(miniMaxRegion, forKey: .miniMaxRegion)
    try container.encode(glmRegion, forKey: .glmRegion)
    try container.encodeIfPresent(appLanguage, forKey: .appLanguage)
    try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
    try container.encode(fairPaceEnabled, forKey: .fairPaceEnabled)
    try container.encode(betaLocalUsageEnabled, forKey: .betaLocalUsageEnabled)
    try container.encode(
      claudeCredentialAccessAuthorized, forKey: .claudeCredentialAccessAuthorized)
    try container.encode(
      legacyKeychainMigrationCompleted, forKey: .legacyKeychainMigrationCompleted)
    try container.encode(betaCostsEnabled, forKey: .betaCostsEnabled)
    try container.encode(menuBarCostMetric, forKey: .menuBarCostMetric)
    try container.encode(costDisplayPeriod, forKey: .costDisplayPeriod)
    try container.encode(watchSettings, forKey: .watchSettings)
  }
}

public struct ConfigurationStore: Sendable {
  private let directory: URL
  private let now: @Sendable () -> Date
  private var configurationURL: URL {
    directory.appending(path: "config.json", directoryHint: .notDirectory)
  }

  public init(
    directory: URL,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.directory = directory
    self.now = now
  }

  public static func applicationSupport() throws -> ConfigurationStore {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true)
    return ConfigurationStore(
      directory: root.appending(
        path: "TokenLink",
        directoryHint: .isDirectory))
  }

  public func load() throws -> AppConfiguration {
    guard FileManager.default.fileExists(atPath: configurationURL.path) else {
      return .default
    }
    do {
      let data = try Data(contentsOf: configurationURL)
      return try JSONDecoder().decode(AppConfiguration.self, from: data)
    } catch is DecodingError {
      let timestamp = Int(now().timeIntervalSince1970)
      let invalidURL = directory.appending(
        path: "config.json.invalid-\(timestamp)",
        directoryHint: .notDirectory)
      if FileManager.default.fileExists(atPath: invalidURL.path) {
        try FileManager.default.removeItem(at: invalidURL)
      }
      try FileManager.default.moveItem(at: configurationURL, to: invalidURL)
      return .default
    }
  }

  public func save(_ configuration: AppConfiguration) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path)

    let temporaryURL = directory.appending(
      path: "config.json.tmp",
      directoryHint: .notDirectory)
    if fileManager.fileExists(atPath: temporaryURL.path) {
      try fileManager.removeItem(at: temporaryURL)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(configuration)
    try data.write(to: temporaryURL, options: .withoutOverwriting)
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: temporaryURL.path)

    if fileManager.fileExists(atPath: configurationURL.path) {
      _ = try fileManager.replaceItemAt(
        configurationURL,
        withItemAt: temporaryURL,
        backupItemName: nil,
        options: [])
    } else {
      try fileManager.moveItem(at: temporaryURL, to: configurationURL)
    }
  }
}
