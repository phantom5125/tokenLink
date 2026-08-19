import Foundation
import TokenLinkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum GLMRegion: String, Codable, Sendable {
  case global
  case china

  public var endpoint: URL {
    switch self {
    case .global:
      URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    case .china:
      URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    }
  }
}

public struct GLMProvider: QuotaProvider {
  public let id: ProviderID = .glm
  private let region: GLMRegion
  private let http: any HTTPClient
  private let credentials: any CredentialReader
  private let now: @Sendable () -> Date

  public init(
    region: GLMRegion,
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
      guard let key = try await credentials.apiKey(for: .glm), !key.isEmpty else {
        return .failure(
          .missingCredential(
            "Configure a GLM Coding Plan API key."))
      }
      var request = URLRequest(url: region.endpoint)
      request.setValue(key, forHTTPHeaderField: "Authorization")
      let response = try await http.data(
        for: request,
        policy: EndpointPolicy(allowedHosts: [
          "api.z.ai",
          "open.bigmodel.cn",
        ]))
      guard response.statusCode == 200 else {
        let authentication = response.statusCode == 401 || response.statusCode == 403
        return .failure(
          .init(
            kind: authentication ? .authentication : .network,
            message: "GLM returned HTTP \(response.statusCode)."))
      }
      return .success(
        try GLMParser.parse(
          data: response.data,
          fetchedAt: now()))
    } catch let failure as ProviderFailure {
      return .failure(failure)
    } catch is DecodingError, is GLMParseError {
      return .failure(.decoding("GLM usage could not be read."))
    } catch {
      return .failure(.network("GLM quota request failed."))
    }
  }
}
