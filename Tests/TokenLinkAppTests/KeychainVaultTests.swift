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

  func set(_ data: Data, service: String, account: String) {
    values[Address(service: service, account: account)] = data
  }

  func value(service: String, account: String) -> Data? {
    values[Address(service: service, account: account)]
  }

  func read(service: String, account: String) async throws -> Data? {
    let address = Address(service: service, account: account)
    lastAddress = address
    return values[address]
  }

  func readByService(service: String) async throws -> Data? { nil }

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

private struct FailingKeychainClient: KeychainClient {
  func read(service: String, account: String) async throws -> Data? {
    throw KeychainClientError(status: -1)
  }
  func readByService(service: String) async throws -> Data? {
    throw KeychainClientError(status: -1)
  }
  func write(_ data: Data, service: String, account: String) async throws {
    throw KeychainClientError(status: -1)
  }
  func delete(service: String, account: String) async throws {
    throw KeychainClientError(status: -1)
  }
}

@Test func keychainUsesFixedServiceAndStableProviderAccount() async throws {
  let client = FakeKeychainClient()
  await client.set(
    Data("legacy-value".utf8),
    service: KeychainVault.legacyService,
    account: "minimax")
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLIToken())

  try await vault.setAPIKey("secret-value", for: .minimax)
  #expect(try await vault.apiKey(for: .minimax) == "secret-value")
  #expect(
    await client.lastAddress
      == .init(
        service: "app.tokenlink.provider",
        account: "minimax"))

  try await vault.deleteAPIKey(for: .minimax)
  #expect(try await vault.apiKey(for: .minimax) == nil)
  #expect(
    await client.value(service: KeychainVault.legacyService, account: "minimax")
      == Data("legacy-value".utf8))
}

@Test func keychainFailureIsReportedAsConfigurationError() async {
  let vault = KeychainVault(
    client: FailingKeychainClient(),
    kimiTokenReader: NoCLIToken())

  do {
    _ = try await vault.apiKey(for: .glm)
    Issue.record("Expected configuration failure")
  } catch let failure as ProviderFailure {
    #expect(failure.kind == .configuration)
  } catch {
    Issue.record("Unexpected error type: \(error)")
  }
}

@Test func legacyTokenLinkServiceIsReadOnlyDuringExplicitMigration() async throws {
  let client = FakeKeychainClient()
  await client.set(
    Data("legacy-secret".utf8),
    service: KeychainVault.legacyService,
    account: "glm")
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLIToken())

  // Normal refresh/status reads only the current TokenLink service.
  #expect(try await vault.apiKey(for: .glm) == nil)
  #expect(await client.value(service: KeychainVault.service, account: "glm") == nil)

  let migrated = try await vault.migrateLegacyAPIKeys(forAccounts: ["glm"])

  #expect(migrated == 1)
  #expect(try await vault.apiKey(for: .glm) == "legacy-secret")
  #expect(
    await client.value(service: KeychainVault.service, account: "glm")
      == Data("legacy-secret".utf8))
  #expect(
    await client.value(service: KeychainVault.legacyService, account: "glm")
      == Data("legacy-secret".utf8))
}

@Test func additionalAccountsAreNamespacedByAccountID() async throws {
  let client = FakeKeychainClient()
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLIToken())
  let defaultAccount = ProviderAccount(provider: .minimax, label: "MiniMax")
  let extraAccount = ProviderAccount(provider: .minimax, label: "Second")

  try await vault.setAPIKey("default-key", for: defaultAccount, isDefault: true)
  #expect(await client.lastAddress?.account == "minimax")

  try await vault.setAPIKey("second-key", for: extraAccount, isDefault: false)
  #expect(
    await client.lastAddress?.account == "minimax.\(extraAccount.id.uuidString)")

  #expect(try await vault.apiKey(for: defaultAccount, isDefault: true) == "default-key")
  #expect(try await vault.apiKey(for: extraAccount, isDefault: false) == "second-key")
}

@Test func environmentFallbackReadsOnlySpecAllowlist() async throws {
  let environment: [String: String] = [
    "ZHIPU_API_KEY": "glm-env-key",
    "MINIMAX_API_KEY": "minimax-env-key",
    "UNRELATED_SECRET": "must-not-be-read",
  ]
  let vault = KeychainVault(
    client: FakeKeychainClient(),
    kimiTokenReader: NoCLIToken(),
    environment: { environment[$0] })

  #expect(try await vault.environmentAPIKey(for: .glm) == "glm-env-key")
  #expect(try await vault.environmentAPIKey(for: .minimax) == "minimax-env-key")
  #expect(try await vault.environmentAPIKey(for: .kimi) == nil)
  #expect(try await vault.environmentAPIKey(for: .codex) == nil)
}

@Test func environmentFallbackFollowsDeclaredPriorityOrder() async throws {
  let environment: [String: String] = [
    "GLM_API_KEY": "third",
    "ZAI_API_KEY": "first",
  ]
  let vault = KeychainVault(
    client: FakeKeychainClient(),
    kimiTokenReader: NoCLIToken(),
    environment: { environment[$0] })

  #expect(try await vault.environmentAPIKey(for: .glm) == "first")
}

@Test func keyHintMasksHeadAndTail() {
  #expect(KeychainVault.keyHint(for: "abcdefghijklmnop") == "abcdefgh…mnop")
  #expect(KeychainVault.keyHint(for: "123456789012") == "12345678…9012")
  #expect(KeychainVault.keyHint(for: "short") == "shor…")
  #expect(KeychainVault.keyHint(for: "abcd") == "abcd…")
  #expect(KeychainVault.keyHint(for: "") == "…")
}

@Test func keyHintReadsStoredKeyAndMasksIt() async throws {
  let client = FakeKeychainClient()
  let vault = KeychainVault(client: client, kimiTokenReader: NoCLIToken())
  let account = ProviderAccount(provider: .glm, label: "GLM")
  try await vault.setAPIKey("glm-secret-key-value", for: account, isDefault: true)

  #expect(try await vault.keyHint(for: account, isDefault: true) == "glm-secr…alue")
  #expect(try await vault.keyHint(forAccount: "kimi") == nil)
}

private actor ServiceOnlyKeychainClient: KeychainClient {
  var byService: [String: Data] = [:]

  func set(_ data: Data, forService service: String) { byService[service] = data }

  func read(service: String, account: String) async throws -> Data? { nil }
  func readByService(service: String) async throws -> Data? { byService[service] }
  func write(_ data: Data, service: String, account: String) async throws {}
  func delete(service: String, account: String) async throws {}
}

@Test func claudeCLIReaderReturnsValidAccessToken() async throws {
  let client = ServiceOnlyKeychainClient()
  await client.set(
    Data(
      #"{"claudeAiOauth":{"accessToken":"oauth-token","refreshToken":"never-read","expiresAt":4102444800000}}"#
        .utf8),
    forService: "Claude Code-credentials")
  let reader = ClaudeCLICredentialReader(
    client: client, now: { Date(timeIntervalSince1970: 1_787_130_000) })

  #expect(try await reader.accessToken() == "oauth-token")
}

@Test func claudeCLIReaderRejectsExpiredToken() async throws {
  let client = ServiceOnlyKeychainClient()
  await client.set(
    Data(
      #"{"claudeAiOauth":{"accessToken":"old-token","expiresAt":1787130000000}}"#.utf8),
    forService: "Claude Code-credentials")
  let reader = ClaudeCLICredentialReader(
    client: client, now: { Date(timeIntervalSince1970: 1_787_130_100) })

  #expect(try await reader.accessToken() == nil)
}

@Test func claudeCLIReaderReturnsNilWithoutItem() async throws {
  let reader = ClaudeCLICredentialReader(client: ServiceOnlyKeychainClient())
  #expect(try await reader.accessToken() == nil)
}
