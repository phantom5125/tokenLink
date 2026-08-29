import Foundation
import Testing
import TokenLinkCore
import TokenLinkProviders

@testable import TokenLinkApp

@Test func configurationRoundTripsWithoutSecrets() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ConfigurationStore(directory: directory)
  var expected = AppConfiguration(
    enabledProviders: [.codex, .kimi],
    refreshMinutes: 5,
    boundDeviceIdentifier: nil,
    codexPath: nil,
    miniMaxRegion: .global,
    glmRegion: .china)
  expected.fairPaceEnabled = true
  expected.betaLocalUsageEnabled = true
  expected.watchSettings = WatchSettings(
    syncedProviders: [.codex, .kimi],
    faceTheme: .pet,
    wakeMode: .tap,
    hourFormat: .h24)

  try store.save(expected)

  #expect(try store.load() == expected)
  let bytes = try Data(contentsOf: directory.appending(path: "config.json"))
  #expect(
    !String(decoding: bytes, as: UTF8.self)
      .localizedCaseInsensitiveContains("apiKey"))
}

@Test func corruptConfigurationIsQuarantinedAndDefaultsAreReturned() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try Data("not-json".utf8).write(to: directory.appending(path: "config.json"))
  let store = ConfigurationStore(directory: directory, now: { Date(timeIntervalSince1970: 42) })

  #expect(try store.load() == .default)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .contains("config.json.invalid-42"))
}

@Test func configurationCanBeReplacedAtomically() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ConfigurationStore(directory: directory)
  var updated = AppConfiguration.default

  try store.save(updated)
  updated.refreshMinutes = 15
  try store.save(updated)

  #expect(try store.load().refreshMinutes == 15)
  #expect(
    !FileManager.default.fileExists(
      atPath: directory.appending(path: "config.json.tmp").path))
}

@Test func legacyEnabledProvidersConfigurationMigratesToAccounts() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let legacy = """
    {
      "enabledProviders" : ["codex", "kimi", "minimax", "glm"],
      "refreshMinutes" : 5,
      "miniMaxRegion" : "china",
      "glmRegion" : "global"
    }
    """
  try Data(legacy.utf8).write(to: directory.appending(path: "config.json"))
  let store = ConfigurationStore(directory: directory)

  let loaded = try store.load()

  #expect(loaded.accounts.map(\.provider) == [.codex, .kimi, .minimax, .glm])
  #expect(loaded.accounts.allSatisfy { $0.enabled })
  #expect(loaded.accounts.map(\.label) == ["Codex", "Kimi", "MiniMax", "GLM"])
  // Claude did not exist when the legacy config was written; migration must
  // not silently enable a provider the user never opted into.
  #expect(loaded.enabledProviders == [.codex, .kimi, .minimax, .glm])
  #expect(!loaded.enabledProviders.contains(.claude))
  #expect(loaded.refreshMinutes == 5)
  #expect(loaded.miniMaxRegion == .china)
  #expect(loaded.glmRegion == .global)
  #expect(loaded.fairPaceEnabled == false)
  #expect(loaded.betaLocalUsageEnabled == false)
  #expect(loaded.watchSettings == WatchSettings())
}

@Test func accountsRoundTripWithStableIDsAndLabels() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ConfigurationStore(directory: directory)
  var expected = AppConfiguration.default
  let extra = ProviderAccount(provider: .kimi, label: "Work", enabled: true)
  expected.accounts.append(extra)
  expected.accounts[0].enabled = false

  try store.save(expected)

  let loaded = try store.load()
  #expect(loaded == expected)
  #expect(loaded.accounts.contains(extra))
  #expect(loaded.enabledProviders == [.kimi, .minimax, .glm, .claude])
}
