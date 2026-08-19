import Foundation
import Testing
import TokenLinkCore
@testable import TokenLinkApp

private actor FakeKeychainClient: KeychainClient {
    struct Address: Hashable, Sendable {
        let service: String
        let account: String
    }

    private var values: [Address: Data] = [:]
    private(set) var lastAddress: Address?

    func read(service: String, account: String) async throws -> Data? {
        let address = Address(service: service, account: account)
        lastAddress = address
        return values[address]
    }

    func write(_ data: Data, service: String, account: String) async throws {
        let address = Address(service: service, account: account)
        lastAddress = address
        values[address] = data
    }

    func delete(service: String, account: String) async throws {
        let address = Address(service: service, account: account)
        lastAddress = address
        values[address] = nil
    }
}

private struct NoCLIToken: KimiTokenReading {
    func accessToken() async throws -> String? { nil }
}

@Test func keychainUsesFixedServiceAndStableProviderAccount() async throws {
    let client = FakeKeychainClient()
    let vault = KeychainVault(client: client, kimiTokenReader: NoCLIToken())

    try await vault.setAPIKey("secret-value", for: .minimax)
    #expect(try await vault.apiKey(for: .minimax) == "secret-value")
    #expect(await client.lastAddress == .init(
        service: "io.github.phantom5125.tokenlink.provider",
        account: "minimax"))

    try await vault.deleteAPIKey(for: .minimax)
    #expect(try await vault.apiKey(for: .minimax) == nil)
}
