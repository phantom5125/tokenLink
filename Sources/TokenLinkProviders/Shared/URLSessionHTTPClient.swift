import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct URLSessionHTTPClient: HTTPClient {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func data(
    for request: URLRequest,
    policy: EndpointPolicy
  ) async throws -> HTTPResponse {
    guard let url = request.url else {
      throw ProviderHostError()
    }
    _ = try policy.validate(url)

    var boundedRequest = request
    boundedRequest.timeoutInterval = 20
    let (data, response) = try await session.data(for: boundedRequest)
    guard let http = response as? HTTPURLResponse else {
      throw ProviderHostError()
    }
    return HTTPResponse(data: data, statusCode: http.statusCode)
  }
}
