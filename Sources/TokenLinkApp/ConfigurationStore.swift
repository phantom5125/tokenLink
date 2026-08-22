import Foundation
import TokenLinkCore
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

public struct AppConfiguration: Codable, Equatable, Sendable {
  /// Accounts are the source of truth for provider enablement; ordered, and
  /// the first account of each provider is its default account.
  public var accounts: [ProviderAccount]
  public var refreshMinutes: Int
  public var boundDeviceIdentifier: UUID?
  public var codexPath: String?
  public var miniMaxRegion: MiniMaxRegion
  public var glmRegion: GLMRegion
  /// nil = follow the system language; otherwise an `AppLanguage` raw value.
  public var appLanguage: String?

  /// Derived from enabled accounts; kept for readable call sites.
  public var enabledProviders: Set<ProviderID> {
    Set(accounts.filter(\.enabled).map(\.provider))
  }

  public init(
    accounts: [ProviderAccount],
    refreshMinutes: Int,
    boundDeviceIdentifier: UUID?,
    codexPath: String?,
    miniMaxRegion: MiniMaxRegion,
    glmRegion: GLMRegion,
    appLanguage: String? = nil
  ) {
    self.accounts = accounts
    self.refreshMinutes = min(60, max(1, refreshMinutes))
    self.boundDeviceIdentifier = boundDeviceIdentifier
    self.codexPath = codexPath
    self.miniMaxRegion = miniMaxRegion
    self.glmRegion = glmRegion
    self.appLanguage = appLanguage
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
    enabledProviders: Set(ProviderID.allCases),
    refreshMinutes: 5,
    boundDeviceIdentifier: nil,
    codexPath: nil,
    miniMaxRegion: .global,
    glmRegion: .global)

  public static func defaultAccounts(for providers: Set<ProviderID>) -> [ProviderAccount] {
    ProviderID.allCases.filter(providers.contains).map { provider in
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
    case codexPath
    case miniMaxRegion
    case glmRegion
    case appLanguage
    case legacyEnabledProviders = "enabledProviders"
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
      accounts = Self.defaultAccounts(for: Set(ProviderID.allCases))
    }
    self.init(
      accounts: accounts,
      refreshMinutes: try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5,
      boundDeviceIdentifier: try container.decodeIfPresent(
        UUID.self, forKey: .boundDeviceIdentifier),
      codexPath: try container.decodeIfPresent(String.self, forKey: .codexPath),
      miniMaxRegion: try container.decodeIfPresent(MiniMaxRegion.self, forKey: .miniMaxRegion)
        ?? .global,
      glmRegion: try container.decodeIfPresent(GLMRegion.self, forKey: .glmRegion) ?? .global,
      appLanguage: try container.decodeIfPresent(String.self, forKey: .appLanguage))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(accounts, forKey: .accounts)
    try container.encode(refreshMinutes, forKey: .refreshMinutes)
    try container.encodeIfPresent(boundDeviceIdentifier, forKey: .boundDeviceIdentifier)
    try container.encodeIfPresent(codexPath, forKey: .codexPath)
    try container.encode(miniMaxRegion, forKey: .miniMaxRegion)
    try container.encode(glmRegion, forKey: .glmRegion)
    try container.encodeIfPresent(appLanguage, forKey: .appLanguage)
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
