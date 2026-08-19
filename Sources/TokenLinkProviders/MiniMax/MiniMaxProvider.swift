import Foundation
import TokenLinkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum MiniMaxRegion: String, Codable, Sendable {
  case global
  case china

  public var endpoint: URL {
    switch self {
    case .global:
      URL(string: "https://www.minimax.io/v1/token_plan/remains")!
    case .china:
      URL(string: "https://platform.minimaxi.com/v1/token_plan/remains")!
    }
  }
}

public struct MiniMaxProvider: QuotaProvider {
  public let id: ProviderID = .minimax
  private let region: MiniMaxRegion
  private let http: any HTTPClient
  private let credentials: any CredentialReader
  private let now: @Sendable () -> Date

  public init(
    region: MiniMaxRegion,
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.region = region
    self.http = http
    self.credentials = credentials
    self.now = now
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    do {
      guard let key = try await credentials.apiKey(for: .minimax), !key.isEmpty else {
        return .failure(
          .missingCredential(
            "Configure a MiniMax Coding Plan API key."))
      }
      var request = URLRequest(url: region.endpoint)
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      let response = try await http.data(
        for: request,
        policy: EndpointPolicy(allowedHosts: [
          "www.minimax.io",
          "platform.minimaxi.com",
        ]))
      guard response.statusCode == 200 else {
        return .failure(
          .init(
            kind: response.statusCode == 401 ? .authentication : .network,
            message: "MiniMax returned HTTP \(response.statusCode)."))
      }
      return .success(
        try MiniMaxParser.parse(
          data: response.data,
          fetchedAt: now()))
    } catch is DecodingError, is MiniMaxParseError {
      return .failure(.decoding("MiniMax usage could not be read."))
    } catch {
      return .failure(.network("MiniMax quota request failed."))
    }
  }
}
