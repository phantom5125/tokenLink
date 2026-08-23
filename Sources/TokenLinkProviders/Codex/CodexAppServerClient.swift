import Foundation

public enum AppServerMessage: Equatable, Sendable {
  case initialize
  case initialized
  case rateLimits(id: Int)
}

public protocol AppServerTransport: Sendable {
  func start(executable: URL) async throws
  func send(_ message: AppServerMessage) async throws
  func response(id: Int, timeout: Duration) async throws -> Data
  func stop() async
}

public enum AppServerClientError: Error, Equatable {
  case missingExecutable
  case timeout
  case notStarted
  case cancelled
  case launchFailed(String)
}

public actor CodexAppServerClient {
  private let transport: any AppServerTransport
  private let timeout: Duration
  private var started = false

  public init(
    transport: any AppServerTransport,
    timeout: Duration = .seconds(15)
  ) {
    self.transport = transport
    self.timeout = timeout
  }

  public func readRateLimits(executable: URL) async throws -> Data {
    guard started == false else {
      throw AppServerClientError.launchFailed("already started")
    }
    started = true
    defer {
      Task { await transport.stop() }
      started = false
    }
    try await transport.start(executable: executable)
    try await transport.send(.initialize)
    try await transport.send(.initialized)
    try await transport.send(.rateLimits(id: 1))
    do {
      return try await transport.response(id: 1, timeout: timeout)
    } catch is CancellationError {
      throw AppServerClientError.cancelled
    } catch {
      throw AppServerClientError.timeout
    }
  }
}
