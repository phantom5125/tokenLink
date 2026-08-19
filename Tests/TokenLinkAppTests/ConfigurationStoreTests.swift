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
    let expected = AppConfiguration(
        enabledProviders: [.codex, .kimi],
        refreshMinutes: 5,
        boundDeviceIdentifier: nil,
        codexPath: nil,
        miniMaxRegion: .global,
        glmRegion: .china)

    try store.save(expected)

    #expect(try store.load() == expected)
    let bytes = try Data(contentsOf: directory.appending(path: "config.json"))
    #expect(!String(decoding: bytes, as: UTF8.self)
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
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .contains("config.json.invalid-42"))
}
