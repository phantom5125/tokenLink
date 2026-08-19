import Foundation
import TokenLinkCore

public struct CodexProvider: QuotaProvider {
  public let id: ProviderID = .codex
  private let client: CodexAppServerClient
  private let now: @Sendable () -> Date
  private let timeout: Duration

  public init(
    executable: URL,
    transport: any AppServerTransport = ProcessAppServerTransport(),
    now: @escaping @Sendable () -> Date = { Date() },
    timeout: Duration = .seconds(5)
  ) {
    self.client = CodexAppServerClient(
      executable: executable,
      transport: transport)
    self.now = now
    self.timeout = timeout
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    do {
      let data = try await client.readRateLimits(timeout: timeout)
      return .success(
        try CodexRateLimitParser.parse(
          data: data,
          fetchedAt: now()))
    } catch AppServerTransportError.timeout {
      return .failure(.timeout("Codex app-server did not respond in time."))
    } catch is CodexRateLimitParseError, is DecodingError {
      return .failure(.decoding("Codex rate limits could not be read."))
    } catch {
      return .failure(.process("Codex app-server could not be queried."))
    }
  }
}
