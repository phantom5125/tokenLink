import Foundation
import TokenLinkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct KimiProvider: QuotaProvider {
  public let id: ProviderID = .kimi
  private let http: any HTTPClient
  private let credentials: any CredentialReader
  private let now: @Sendable () -> Date

  public init(
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.http = http
    self.credentials = credentials
    self.now = now
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    do {
      let explicit = try await credentials.apiKey(for: .kimi)
      let token: String?
      if let explicit {
        token = explicit
      } else {
        token = try await credentials.cliAccessToken(for: .kimi)
      }
      guard let token, !token.isEmpty else {
        return .failure(
          .missingCredential(
            "Configure a Kimi Coding API key or sign in with Kimi Code CLI."))
      }

      var request = URLRequest(
        url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      let response = try await http.data(
        for: request,
        policy: .init(allowedHosts: ["api.kimi.com"]))
      guard response.statusCode == 200 else {
        return .failure(
          .init(
            kind: response.statusCode == 401 ? .authentication : .network,
            message: "Kimi returned HTTP \(response.statusCode)."))
      }
      return .success(
        try KimiParser.parse(
          data: response.data,
          fetchedAt: now(),
          source: explicit == nil ? .cliCredential : .apiKey))
    } catch let failure as ProviderFailure {
      return .failure(failure)
    } catch is DecodingError, is KimiParseError {
      return .failure(.decoding("Kimi usage could not be read."))
    } catch {
      return .failure(.network("Kimi quota request failed."))
    }
  }
}
