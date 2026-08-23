import Foundation
import TokenLinkCore

public enum MiniMaxRegion: String, Codable, Sendable { case global, china }

public struct MiniMaxProvider: QuotaProvider {
  public let id: ProviderID = .minimax
  let region: MiniMaxRegion
  let http: any HTTPClient
  let credentials: any CredentialReader
  let now: @Sendable () -> Date

  var endpoint: URL {
    switch region {
    case .global: URL(string: "https://www.minimax.io/v1/token_plan/remains")!
    case .china: URL(string: "https://platform.minimaxi.com/v1/token_plan/remains")!
    }
  }

  public init(
    region: MiniMaxRegion,
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.region = region
    self.http = http
    self.credentials = credentials
    self.now = now
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    do {
      guard let key = try await credentials.apiKey(for: .minimax), !key.isEmpty else {
        return .failure(.missingCredential("Configure a MiniMax Coding Plan API key."))
      }
      var request = URLRequest(url: endpoint)
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      let policy = EndpointPolicy(allowedHosts: ["www.minimax.io", "platform.minimaxi.com"])
      let response = try await http.data(for: request, policy: policy)
      guard response.statusCode == 200 else {
        return .failure(
          .init(
            kind: response.statusCode == 401 ? .authentication : .network,
            message: "MiniMax returned HTTP \(response.statusCode)."))
      }
      return .success(try MiniMaxParser.parse(data: response.data, fetchedAt: now()))
    } catch {
      return .failure(.init(kind: .decoding, message: "MiniMax usage could not be read."))
    }
  }
}
