import Foundation
import TokenLinkCore
import TokenLinkProviders

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var enabledProviders: Set<ProviderID>
    public var refreshMinutes: Int
    public var boundDeviceIdentifier: UUID?
    public var codexPath: String?
    public var miniMaxRegion: MiniMaxRegion
    public var glmRegion: GLMRegion

    public init(
        enabledProviders: Set<ProviderID>,
        refreshMinutes: Int,
        boundDeviceIdentifier: UUID?,
        codexPath: String?,
        miniMaxRegion: MiniMaxRegion,
        glmRegion: GLMRegion
    ) {
        self.enabledProviders = enabledProviders
        self.refreshMinutes = min(60, max(1, refreshMinutes))
        self.boundDeviceIdentifier = boundDeviceIdentifier
        self.codexPath = codexPath
        self.miniMaxRegion = miniMaxRegion
        self.glmRegion = glmRegion
    }

    public static let `default` = AppConfiguration(
        enabledProviders: Set(ProviderID.allCases),
        refreshMinutes: 5,
        boundDeviceIdentifier: nil,
        codexPath: nil,
        miniMaxRegion: .global,
        glmRegion: .global)
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
        return ConfigurationStore(directory: root.appending(
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
