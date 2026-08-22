import Foundation
import TokenLinkCore

public enum GLMRegion: String, Codable, Sendable { case global, china }

extension GLMRegion {
    var endpoint: URL {
        switch self {
        case .global: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
        case .china: URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
        }
    }
}

public struct GLMProvider: QuotaProvider {
    public let id: ProviderID = .glm
    let region: GLMRegion
    let http: any HTTPClient
    let credentials: any CredentialReader
    let now: @Sendable () -> Date

    public init(
        region: GLMRegion,
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
            guard let key = try await credentials.apiKey(for: .glm), !key.isEmpty else {
                return .failure(.missingCredential("Configure a GLM Coding Plan API key."))
            }
            var request = URLRequest(url: region.endpoint)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let policy = EndpointPolicy(allowedHosts: ["api.z.ai", "open.bigmodel.cn"])
            let response = try await http.data(for: request, policy: policy)
            switch response.statusCode {
            case 200:
                return .success(try GLMParser.parse(data: response.data, fetchedAt: now()))
            case 401, 403:
                return .failure(.init(kind: .authentication,
                                      message: "GLM returned HTTP \(response.statusCode)."))
            default:
                return .failure(.init(kind: .network,
                                      message: "GLM returned HTTP \(response.statusCode)."))
            }
        } catch {
            return .failure(.init(kind: .decoding, message: "GLM usage could not be read."))
        }
    }
}