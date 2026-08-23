import Foundation
import TokenLinkCore
import TokenLinkProviders

/// 非敏感应用配置。API Key 永远不进 JSON——它们只存在于 Keychain。
public struct AppConfiguration: Codable, Equatable, Sendable {
  public var enabledProviders: [ProviderID]
  public var refreshMinutes: Int
  public var boundDeviceIdentifier: UUID?
  public var codexPath: String?
  public var miniMaxRegion: MiniMaxRegion
  public var glmRegion: GLMRegion

  public init(
    enabledProviders: [ProviderID] = ProviderID.allCases,
    refreshMinutes: Int = 5,
    boundDeviceIdentifier: UUID? = nil,
    codexPath: String? = nil,
    miniMaxRegion: MiniMaxRegion = .global,
    glmRegion: GLMRegion = .china
  ) {
    self.enabledProviders = enabledProviders
    self.refreshMinutes = refreshMinutes
    self.boundDeviceIdentifier = boundDeviceIdentifier
    self.codexPath = codexPath
    self.miniMaxRegion = miniMaxRegion
    self.glmRegion = glmRegion
  }
}

/// 原子写入的配置存储：写入 config.json.tmp 后整体替换，避免半截文件。
public struct ConfigurationStore: Sendable {
  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  private var configURL: URL { directory.appending(path: "config.json") }

  public func load() -> AppConfiguration {
    guard let data = try? Data(contentsOf: configURL) else { return AppConfiguration() }
    do {
      return try JSONDecoder().decode(AppConfiguration.self, from: data)
    } catch {
      // 损坏的配置不丢用户现场：改名保留，回退默认值。
      let stamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
      let invalid = directory.appending(path: "config.json.invalid-\(stamp)")
      try? FileManager.default.moveItem(at: configURL, to: invalid)
      return AppConfiguration()
    }
  }

  public func save(_ configuration: AppConfiguration) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let data = try JSONEncoder().encode(configuration)
    let temporary = directory.appending(path: "config.json.tmp")
    try data.write(to: temporary, options: .atomic)
    if FileManager.default.fileExists(atPath: configURL.path) {
      _ = try FileManager.default.replaceItemAt(configURL, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: configURL)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: configURL.path)
  }
}
