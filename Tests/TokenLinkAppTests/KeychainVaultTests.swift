import Foundation
import Security
import Testing
@testable import TokenLinkApp
@testable import TokenLinkCore
@testable import TokenLinkProviders

/// 内存 fake：测试绝不触碰真实登录 Keychain。
private final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    private static func key(_ query: [String: Any]) -> String {
        let service = query[kSecAttrService as String] as? String ?? ""
        let account = query[kSecAttrAccount as String] as? String ?? ""
        return "\(service)|\(account)"
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lock.lock(); defer { lock.unlock() }
        if let data = storage[Self.key(query)] { return (errSecSuccess, data as CFData) }
        return (errSecItemNotFound, nil)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(attributes)
        guard storage[key] == nil, let data = attributes[kSecValueData as String] as? Data else {
            return errSecDuplicateItem
        }
        storage[key] = data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(query)
        guard storage[key] != nil, let data = attributes[kSecValueData as String] as? Data else {
            return errSecItemNotFound
        }
        storage[key] = data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        let removed = storage.removeValue(forKey: Self.key(query)) != nil
        return removed ? errSecSuccess : errSecItemNotFound
    }
}

private func makeVault() -> KeychainVault {
    let emptyHome = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return KeychainVault(
        client: FakeKeychainClient(),
        cliReader: KimiCLICredentialReader(homeDirectory: emptyHome))
}

@Test func apiKeyRoundTripsThroughUpdateThenAddFallback() async throws {
    let vault = makeVault()
    #expect(try await vault.apiKey(for: .minimax) == nil)
    try vault.setAPIKey("key-one", for: .minimax)
    #expect(try await vault.apiKey(for: .minimax) == "key-one")
    // 更新已存在的条目走 SecItemUpdate 分支
    try vault.setAPIKey("key-two", for: .minimax)
    #expect(try await vault.apiKey(for: .minimax) == "key-two")
}

@Test func keysAreIsolatedPerProvider() async throws {
    let vault = makeVault()
    try vault.setAPIKey("kimi-key", for: .kimi)
    try vault.setAPIKey("glm-key", for: .glm)
    #expect(try await vault.apiKey(for: .kimi) == "kimi-key")
    #expect(try await vault.apiKey(for: .glm) == "glm-key")
    try vault.deleteAPIKey(for: .kimi)
    #expect(try await vault.apiKey(for: .kimi) == nil)
    #expect(try await vault.apiKey(for: .glm) == "glm-key")
}

@Test func cliAccessTokenIsKimiOnly() async throws {
    let vault = makeVault()
    // 空 home：没有 CLI 凭据文件时应抛错或返回 nil，但绝不能去读真实 home。
    #expect(try await vault.cliAccessToken(for: .minimax) == nil)
    #expect(try await vault.cliAccessToken(for: .codex) == nil)
}
