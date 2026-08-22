import Foundation

public struct KimiCLICredentialReader: Sendable {
    private let homeDirectory: URL
    private let now: @Sendable () -> Date

    public init(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.homeDirectory = homeDirectory
        self.now = now
    }

    public func currentAccessToken() throws -> String? {
        let credentialsURL = homeDirectory
            .appending(path: ".kimi-code")
            .appending(path: "credentials")
            .appending(path: "kimi-code.json")
        let data = try Data(contentsOf: credentialsURL)
        let payload = try JSONDecoder().decode(KimiCLICredentials.self, from: data)
        // Expire check
        if let expiresAt = payload.expiresAt, expiresAt <= now() { return nil }
        let token = payload.accessToken
        return token.isEmpty ? nil : token
    }
}

private struct KimiCLICredentials: Decodable {
    let accessToken: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        if let string = try? container.decode(String.self, forKey: .expiresAt) {
            self.expiresAt = KimiCLICredentialReader.parseISO8601(string)
        } else if let timestamp = try? container.decode(Double.self, forKey: .expiresAt) {
            self.expiresAt = Date(timeIntervalSince1970: timestamp)
        } else {
            self.expiresAt = nil
        }
    }
}

extension KimiCLICredentialReader {
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}