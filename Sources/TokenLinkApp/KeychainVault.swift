import Foundation
import Security
import TokenLinkCore
import TokenLinkProviders

public protocol KeychainClient: Sendable {
  func read(service: String, account: String) async throws -> Data?
  /// Reads an item matched by service only (no account constraint), used for
  /// credentials owned by other apps such as Claude Code.
  func readByService(service: String) async throws -> Data?
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

  public func readByService(service: String) async throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
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
      kSecValueData as String: data
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

public protocol ClaudeTokenReading: Sendable {
  func accessToken() async throws -> String?
}

/// Reads the Claude Code CLI OAuth credential from the macOS Keychain item
/// the CLI maintains (service `Claude Code-credentials`). Only the current
/// access token is returned; the refresh token is never decoded or exposed.
public struct ClaudeCLICredentialReader: ClaudeTokenReading {
  public static let service = "Claude Code-credentials"

  private let client: any KeychainClient
  private let now: @Sendable () -> Date

  public init(
    client: any KeychainClient = SystemKeychainClient(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.client = client
    self.now = now
  }

  public func accessToken() async throws -> String? {
    guard let data = try await client.readByService(service: Self.service) else { return nil }
    let credential = try JSONDecoder().decode(ClaudeKeychainCredential.self, from: data)
    guard let oauth = credential.claudeAiOauth, !oauth.accessToken.isEmpty else { return nil }
    if let expiresAt = oauth.expiresAt,
      Date(timeIntervalSince1970: expiresAt / 1_000) <= now()
    {
      return nil
    }
    return oauth.accessToken
  }
}

/// Deliberately omits `refreshToken`: it is never read out of the item.
private struct ClaudeKeychainCredential: Decodable {
  let claudeAiOauth: OAuth?

  struct OAuth: Decodable {
    let accessToken: String
    /// Milliseconds since 1970.
    let expiresAt: Double?
  }
}

public struct KeychainVault: CredentialReader, Sendable {
  public static let service = "io.github.phantom5125.tokenlink.provider"

  private let client: any KeychainClient
  private let kimiTokenReader: any KimiTokenReading
  private let claudeTokenReader: any ClaudeTokenReading
  private let environment: @Sendable (String) -> String?

  public init(
    client: any KeychainClient = SystemKeychainClient(),
    kimiTokenReader: any KimiTokenReading = KimiCLICredentialReader(
      homeURL: FileManager.default.homeDirectoryForCurrentUser),
    claudeTokenReader: (any ClaudeTokenReading)? = nil,
    environment: @escaping @Sendable (String) -> String? = {
      ProcessInfo.processInfo.environment[$0]
    }
  ) {
    self.client = client
    self.kimiTokenReader = kimiTokenReader
    self.claudeTokenReader = claudeTokenReader ?? ClaudeCLICredentialReader(client: client)
    self.environment = environment
  }

  /// Keychain account naming: the default account of a provider keeps the
  /// historical `provider.rawValue` name so existing stored keys keep working;
  /// additional accounts are namespaced by their account id.
  public static func keychainAccountName(
    provider: ProviderID,
    accountID: UUID,
    isDefault: Bool
  ) -> String {
    isDefault ? provider.rawValue : "\(provider.rawValue).\(accountID.uuidString)"
  }

  public func apiKey(forAccount account: String) async throws -> String? {
    do {
      guard
        let data = try await client.read(
          service: Self.service,
          account: account)
      else { return nil }
      guard let value = String(data: data, encoding: .utf8) else {
        throw ProviderFailure.configuration("Keychain value is not valid UTF-8.")
      }
      return value
    } catch let failure as ProviderFailure {
      throw failure
    } catch {
      throw ProviderFailure.configuration("Keychain access failed.")
    }
  }

  public func apiKey(for account: ProviderAccount, isDefault: Bool) async throws -> String? {
    try await apiKey(
      forAccount: Self.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: isDefault))
  }

  public func cliAccessToken(for provider: ProviderID) async throws -> String? {
    switch provider {
    case .kimi:
      return try await kimiTokenReader.accessToken()
    case .claude:
      return try await claudeTokenReader.accessToken()
    default:
      return nil
    }
  }

  /// Reads only the environment variables declared in the provider's spec.
  public func environmentAPIKey(for provider: ProviderID) async throws -> String? {
    guard let spec = ProviderRegistry.spec(for: provider) else { return nil }
    for name in spec.credentialEnvVars {
      if let value = environment(name), !value.isEmpty {
        return value
      }
    }
    return nil
  }

  public func setAPIKey(_ value: String, forAccount account: String) async throws {
    do {
      try await client.write(
        Data(value.utf8),
        service: Self.service,
        account: account)
    } catch {
      throw ProviderFailure.configuration("Keychain update failed.")
    }
  }

  public func setAPIKey(_ value: String, for provider: ProviderID) async throws {
    try await setAPIKey(value, forAccount: provider.rawValue)
  }

  public func setAPIKey(
    _ value: String,
    for account: ProviderAccount,
    isDefault: Bool
  ) async throws {
    try await setAPIKey(
      value,
      forAccount: Self.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: isDefault))
  }

  public func deleteAPIKey(forAccount account: String) async throws {
    do {
      try await client.delete(
        service: Self.service,
        account: account)
    } catch {
      throw ProviderFailure.configuration("Keychain deletion failed.")
    }
  }

  public func deleteAPIKey(for provider: ProviderID) async throws {
    try await deleteAPIKey(forAccount: provider.rawValue)
  }

  public func deleteAPIKey(for account: ProviderAccount, isDefault: Bool) async throws {
    try await deleteAPIKey(
      forAccount: Self.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: isDefault))
  }

  /// Display-only mask: first 8 + "…" + last 4 characters. Keys shorter than
  /// 12 characters show only their first 4 characters plus the ellipsis.
  public static func keyHint(for key: String) -> String {
    if key.count < 12 {
      return String(key.prefix(4)) + "…"
    }
    return String(key.prefix(8)) + "…" + String(key.suffix(4))
  }

  public func keyHint(forAccount account: String) async throws -> String? {
    guard let key = try await apiKey(forAccount: account) else { return nil }
    return Self.keyHint(for: key)
  }

  public func keyHint(for account: ProviderAccount, isDefault: Bool) async throws -> String? {
    try await keyHint(
      forAccount: Self.keychainAccountName(
        provider: account.provider,
        accountID: account.id,
        isDefault: isDefault))
  }
}
