import Foundation
import Security
import TokenLinkCore
import TokenLinkProviders

public protocol KeychainClient: Sendable {
    func read(service: String, account: String) async throws -> Data?
    func write(_ data: Data, service: String, account: String) async throws
    func delete(service: String, account: String) async throws
}

public struct SystemKeychainClient: KeychainClient {
    public init() {}

    public func read(service: String, account: String) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainClientError(status: status)
        }
        return data
    }

    public func write(_ data: Data, service: String, account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
        ]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainClientError(status: status)
        }
    }

    public func delete(service: String, account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainClientError(status: status)
        }
    }
}

public struct KeychainClientError: Error, Equatable, Sendable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
}

public protocol KimiTokenReading: Sendable {
    func accessToken() async throws -> String?
}

extension KimiCLICredentialReader: KimiTokenReading {}

public struct KeychainVault: CredentialReader, Sendable {
    public static let service = "io.github.phantom5125.tokenlink.provider"

    private let client: any KeychainClient
    private let kimiTokenReader: any KimiTokenReading

    public init(
        client: any KeychainClient = SystemKeychainClient(),
        kimiTokenReader: any KimiTokenReading = KimiCLICredentialReader(
            homeURL: FileManager.default.homeDirectoryForCurrentUser)
    ) {
        self.client = client
        self.kimiTokenReader = kimiTokenReader
    }

    public func apiKey(for provider: ProviderID) async throws -> String? {
        guard let data = try await client.read(
            service: Self.service,
            account: provider.rawValue) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw ProviderFailure.configuration("Keychain value is not valid UTF-8.")
        }
        return value
    }

    public func cliAccessToken(for provider: ProviderID) async throws -> String? {
        guard provider == .kimi else { return nil }
        return try await kimiTokenReader.accessToken()
    }

    public func setAPIKey(_ value: String, for provider: ProviderID) async throws {
        try await client.write(
            Data(value.utf8),
            service: Self.service,
            account: provider.rawValue)
    }

    public func deleteAPIKey(for provider: ProviderID) async throws {
        try await client.delete(
            service: Self.service,
            account: provider.rawValue)
    }
}
