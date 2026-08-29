import Foundation

public struct KimiCLICredentialReader: Sendable {
  private let homeURL: URL
  private let now: @Sendable () -> Date

  public init(
    homeURL: URL,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.homeURL = homeURL
    self.now = now
  }

  public func accessToken() async throws -> String? {
    let url =
      homeURL
      .appending(path: ".kimi-code", directoryHint: .isDirectory)
      .appending(path: "credentials", directoryHint: .isDirectory)
      .appending(path: "kimi-code.json", directoryHint: .notDirectory)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }

    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let credential = try JSONDecoder().decode(Credential.self, from: data)
    guard !credential.accessToken.isEmpty else { return nil }
    if let expiry = credential.expiryDate, expiry <= now() { return nil }
    return credential.accessToken
  }
}

private struct Credential: Decodable {
  let accessToken: String
  let expiresAt: FlexibleExpiry?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case expiresAt = "expires_at"
  }

  var expiryDate: Date? { expiresAt?.date }
}

private struct FlexibleExpiry: Decodable {
  let date: Date

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let seconds = try? container.decode(Double.self) {
      self.date = Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
    } else if let text = try? container.decode(String.self),
      let date = ISO8601DateFormatter().date(from: text)
    {
      self.date = date
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported Kimi credential expiry.")
    }
  }
}
