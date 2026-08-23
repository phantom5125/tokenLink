import Foundation
import TokenLinkCore

public struct CodexProvider: QuotaProvider {
  public let id: ProviderID = .codex

  private let executable: URL
  private let transport: any AppServerTransport
  private let timeout: Duration
  private let now: @Sendable () -> Date

  public init(
    executable: URL,
    transport: any AppServerTransport,
    timeout: Duration = .seconds(15),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.executable = executable
    self.transport = transport
    self.timeout = timeout
    self.now = now
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    let result = await performFetch()
    await transport.stop()
    return result
  }

  private func performFetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    do {
      try await transport.start(executable: executable)
      try await transport.send(.initialize)
      try await transport.send(.initialized)
      try await transport.send(.rateLimits(id: 1))
      let data: Data
      do {
        data = try await transport.response(id: 1, timeout: timeout)
      } catch is CancellationError {
        return .failure(
          .init(
            kind: .timeout,
            message: "Codex app server timed out."))
      } catch let error as AppServerClientError where error == .timeout {
        return .failure(
          .init(
            kind: .timeout,
            message: "Codex app server timed out."))
      } catch {
        return .failure(
          .init(
            kind: .timeout,
            message: "Codex app server timed out."))
      }
      let snapshot = try CodexRateLimitParser.parse(data: data, fetchedAt: now())
      return .success(snapshot)
    } catch let failure as ProviderFailure {
      return .failure(failure)
    } catch let error as AppServerClientError {
      switch error {
      case .timeout, .cancelled:
        return .failure(
          .init(
            kind: .timeout,
            message: "Codex app server timed out."))
      case .missingExecutable:
        return .failure(
          .init(
            kind: .missingCredential,
            message: "Codex CLI not found. Install the Codex CLI or set a custom path."))
      default:
        return .failure(
          .init(
            kind: .process,
            message: "Codex app server failed to launch."))
      }
    } catch {
      return .failure(
        .init(
          kind: .decoding,
          message: "Codex usage could not be read."))
    }
  }
}

public actor ProcessAppServerTransport: AppServerTransport {
  private var process: Process?
  private var stdin: Pipe?
  private var stdout: Pipe?
  private var stderr: Pipe?

  public init() {}

  public func start(executable: URL) async throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["app-server", "--listen", "stdio://"]
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    do {
      try process.run()
    } catch {
      throw AppServerClientError.launchFailed(error.localizedDescription)
    }
    self.process = process
    self.stdin = stdin
    self.stdout = stdout
    self.stderr = stderr
  }

  public func send(_ message: AppServerMessage) async throws {
    guard let stdin else { throw AppServerClientError.notStarted }
    let object: [String: Any]
    switch message {
    case .initialize:
      object = [
        "method": "initialize",
        "id": 0,
        "params": [
          "clientInfo": [
            "name": "tokenlink",
            "title": "TokenLink",
            "version": "0.1.0",
          ]
        ],
      ]
    case .initialized:
      object = [
        "method": "initialized",
        "params": [:],
      ]
    case .rateLimits(let id):
      object = [
        "method": "account/rateLimits/read",
        "id": id,
        "params": [:],
      ]
    }
    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.withoutEscapingSlashes])
    var line = data
    line.append(0x0A)
    try stdin.fileHandleForWriting.write(contentsOf: line)
  }

  public func response(id: Int, timeout: Duration) async throws -> Data {
    guard let stdout else { throw AppServerClientError.notStarted }
    return try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        try await self.readLine(matching: id, stdout: stdout)
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw AppServerClientError.timeout
      }
      guard let result = try await group.next() else {
        throw AppServerClientError.timeout
      }
      group.cancelAll()
      return result
    }
  }

  private func readLine(matching id: Int, stdout: Pipe) async throws -> Data {
    let handle = stdout.fileHandleForReading
    var buffer = Data()
    while true {
      let chunk = try handle.read(upToCount: 4096) ?? Data()
      if chunk.isEmpty { break }
      buffer.append(chunk)
      while let newlineIndex = buffer.firstIndex(of: 0x0A) {
        let line = buffer.prefix(upTo: newlineIndex)
        buffer.removeSubrange(buffer.startIndex...newlineIndex)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let responseId = object["id"] as? Int,
          responseId == id
        else {
          continue
        }
        return line
      }
    }
    throw AppServerClientError.cancelled
  }

  public func stop() async {
    guard let process else { return }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    try? stdin?.fileHandleForWriting.close()
    try? stdout?.fileHandleForReading.close()
    try? stderr?.fileHandleForReading.close()
    self.process = nil
    self.stdin = nil
    self.stdout = nil
    self.stderr = nil
  }
}
