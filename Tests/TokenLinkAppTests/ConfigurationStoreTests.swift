import Foundation
import Testing
@testable import TokenLinkApp
@testable import TokenLinkCore
@testable import TokenLinkProviders

@Test func configurationRoundTripsWithoutSecrets() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = ConfigurationStore(directory: directory)
    let expected = AppConfiguration(enabledProviders: [.codex, .kimi], refreshMinutes: 5,
                                    boundDeviceIdentifier: nil, codexPath: nil,
                                    miniMaxRegion: .global, glmRegion: .china)
    try store.save(expected)
    #expect(try store.load() == expected)
    let bytes = try Data(contentsOf: directory.appending(path: "config.json"))
    #expect(!String(decoding: bytes, as: UTF8.self).localizedCaseInsensitiveContains("apiKey"))
}

@Test func missingConfigReturnsDefaults() {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = ConfigurationStore(directory: directory)
    #expect(store.load() == AppConfiguration())
}

@Test func corruptConfigIsMovedAsideAndDefaultsReturned() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configURL = directory.appending(path: "config.json")
    try Data("not json".utf8).write(to: configURL)
    let store = ConfigurationStore(directory: directory)
    #expect(store.load() == AppConfiguration())
    #expect(!FileManager.default.fileExists(atPath: configURL.path))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(leftovers.contains { $0.hasPrefix("config.json.invalid-") })
}

@Test func repeatedSavesReplaceAtomically() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = ConfigurationStore(directory: directory)
    try store.save(AppConfiguration(refreshMinutes: 5))
    try store.save(AppConfiguration(refreshMinutes: 15))
    #expect(store.load().refreshMinutes == 15)
    // 不残留临时文件
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(!files.contains("config.json.tmp"))
}
