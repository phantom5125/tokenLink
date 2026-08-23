import Foundation
import Security
import TokenLinkCore
import TokenLinkProviders

/// Security 框架的薄封装，便于测试注入 fake，不碰真实登录 Keychain。
public protocol KeychainClient: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    @discardableResult func add(_ attributes: [String: Any]) -> OSStatus
    @discardableResult func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    @discardableResult func delete(_ query: [String: Any]) -> OSStatus
}

public struct SystemKeychainClient: KeychainClient {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Provider API Key 的 Keychain 存取。固定 service 命名空间，account 即 ProviderID。
public struct KeychainVault: CredentialReader, Sendable {
    public static let service = "io.github.phantom5125.tokenlink.provider"

    private let client: any KeychainClient
    private let cliReader: KimiCLICredentialReader

    public init(
        client: any KeychainClient = SystemKeychainClient(),
        cliReader: KimiCLICredentialReader = KimiCLICredentialReader()
    ) {
        self.client = client
        self.cliReader = cliReader
    }

    private func query(for provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    public func apiKey(for provider: ProviderID) async throws -> String? {
        var attributes = query(for: provider)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = client.copyMatching(attributes)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw ProviderFailure(kind: .configuration, message: "Keychain access failed.")
        }
        return value
    }

    public func setAPIKey(_ value: String, for provider: ProviderID) throws {
        let data = Data(value.utf8)
        let status = client.update(
            query(for: provider), attributes: [kSecValueData as String: data])
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var attributes = query(for: provider)
            attributes[kSecValueData as String] = data
            guard client.add(attributes) == errSecSuccess else {
                throw ProviderFailure(kind: .configuration, message: "Keychain write failed.")
            }
            return
        }
        throw ProviderFailure(kind: .configuration, message: "Keychain write failed.")
    }

    public func deleteAPIKey(for provider: ProviderID) throws {
        let status = client.delete(query(for: provider))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderFailure(kind: .configuration, message: "Keychain delete failed.")
        }
    }

    public func cliAccessToken(for provider: ProviderID) async throws -> String? {
        guard provider == .kimi else { return nil }
        return try cliReader.currentAccessToken()
    }
}
