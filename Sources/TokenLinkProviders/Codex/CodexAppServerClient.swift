import Foundation

/// Resolves the Codex executable used for both quota and session polling.
/// An explicit user path wins. Otherwise prefer Codex Desktop's bundled CLI:
/// it tracks the Desktop task store and can see sessions that an unrelated,
/// older CLI earlier on PATH cannot.
public enum CodexExecutableResolver {
  public static func candidatePaths(
    configuredPath: String?,
    environmentPath: String?,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> [String] {
    var candidates: [String] = []
    if let configuredPath, !configuredPath.isEmpty {
      candidates.append(configuredPath)
    }
    candidates.append(contentsOf: [
      "/Applications/Codex.app/Contents/Resources/codex",
      "/Applications/ChatGPT.app/Contents/Resources/codex",
      homeDirectory.appending(path: "Applications/Codex.app/Contents/Resources/codex").path,
      homeDirectory.appending(path: "Applications/ChatGPT.app/Contents/Resources/codex").path,
    ])
    candidates.append(
      contentsOf: environmentPath?
        .split(separator: ":")
        .map { "\($0)/codex" } ?? [])
    candidates.append(contentsOf: [
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      homeDirectory.appending(path: ".local/bin/codex").path,
    ])
    return candidates
  }

  public static func resolve(
    configuredPath: String?,
    environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
    fileManager: FileManager = .default
  ) -> URL {
    let candidates = candidatePaths(
      configuredPath: configuredPath,
      environmentPath: environmentPath,
      homeDirectory: fileManager.homeDirectoryForCurrentUser)
    if let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) {
      return URL(filePath: path)
    }
    return URL(filePath: "/usr/local/bin/codex")
  }
}

public protocol AppServerTransport: Sendable {
  func start(executable: URL) async throws
  func send(_ message: AppServerMessage) async throws
  func response(id: Int, timeout: Duration) async throws -> Data
  func stop() async
}

public enum AppServerMessage: Equatable, Sendable {
  case initialize
  case initialized
  case rateLimits(id: Int)
  case threadList(id: Int, limit: Int)

  func jsonLine() throws -> Data {
    let object: [String: Any]
    switch self {
    case .initialize:
      object = [
        "method": "initialize",
        "id": 0,
        "params": [
          "clientInfo": [
            "name": "tokenlink",
            "title": "TokenLink",
            "version": "0.2.0",
          ]
        ],
      ]
    case .initialized:
      object = [
        "method": "initialized",
        "params": [:] as [String: String],
      ]
    case .rateLimits(let id):
      object = [
        "method": "account/rateLimits/read",
        "id": id,
        "params": [:] as [String: String],
      ]
    case .threadList(let id, let limit):
      object = [
        "method": "thread/list",
        "id": id,
        "params": ["limit": limit],
      ]
    }
    var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    data.append(0x0A)
    return data
  }
}

public enum AppServerTransportError: Error, Equatable, Sendable {
  case timeout
  case notRunning
  case malformedResponse
  case launch(String)
  case terminated(String)
}

public actor ProcessAppServerTransport: AppServerTransport {
  private var process: Process?
  private var input: FileHandle?
  private var readerTasks: [Task<Void, Never>] = []
  private let responses = JSONLResponseBuffer()
  private let stderrTail = BoundedTextBuffer(limit: 2_000)
  /// Extra variables merged over the inherited environment, e.g. proxy
  /// settings for CLI HTTP stacks that ignore macOS system proxy preferences.
  private let extraEnvironment: [String: String]

  public init(extraEnvironment: [String: String] = [:]) {
    self.extraEnvironment = extraEnvironment
  }

  public func start(executable: URL) async throws {
    if process != nil { await stop() }

    let process = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = executable
    process.arguments = ["app-server", "--listen", "stdio://"]
    if !extraEnvironment.isEmpty {
      process.environment = ProcessInfo.processInfo.environment.merging(extraEnvironment) {
        _, new in new
      }
    }
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw AppServerTransportError.launch(error.localizedDescription)
    }

    self.process = process
    self.input = stdin.fileHandleForWriting
    let responseBuffer = responses
    let errorBuffer = stderrTail
    let stdoutHandle = stdout.fileHandleForReading
    let stderrHandle = stderr.fileHandleForReading
    readerTasks = [
      Task.detached {
        while !Task.isCancelled {
          let data = stdoutHandle.availableData
          if data.isEmpty { break }
          await responseBuffer.append(data)
        }
      },
      Task.detached {
        while !Task.isCancelled {
          let data = stderrHandle.availableData
          if data.isEmpty { break }
          await errorBuffer.append(data)
        }
      },
    ]
  }

  public func send(_ message: AppServerMessage) async throws {
    guard let process, process.isRunning, let input else {
      throw AppServerTransportError.notRunning
    }
    do {
      try input.write(contentsOf: message.jsonLine())
    } catch {
      throw AppServerTransportError.terminated(error.localizedDescription)
    }
  }

  public func response(id: Int, timeout: Duration) async throws -> Data {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      try Task.checkCancellation()
      if let line = await responses.takeResponse(id: id) {
        return line
      }
      if let process, !process.isRunning {
        let tail = await stderrTail.text()
        throw AppServerTransportError.terminated(tail)
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw AppServerTransportError.timeout
  }

  public func stop() async {
    try? input?.close()
    if let process, process.isRunning {
      process.terminate()
    }
    for task in readerTasks { task.cancel() }
    readerTasks.removeAll()
    input = nil
    process = nil
    await responses.reset()
  }
}

public struct CodexAppServerClient: Sendable {
  private let executable: URL
  private let transport: any AppServerTransport

  public init(executable: URL, transport: any AppServerTransport) {
    self.executable = executable
    self.transport = transport
  }

  public func readRateLimits(
    startupTimeout: Duration = .seconds(30),
    requestTimeout: Duration = .seconds(5)
  ) async throws -> Data {
    try await roundTrip(
      message: .rateLimits(id: 1),
      id: 1,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout)
  }

  public func listThreads(
    limit: Int,
    startupTimeout: Duration = .seconds(30),
    requestTimeout: Duration = .seconds(5)
  ) async throws -> Data {
    try await roundTrip(
      message: .threadList(id: 2, limit: limit),
      id: 2,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout)
  }

  private func roundTrip(
    message: AppServerMessage,
    id: Int,
    startupTimeout: Duration,
    requestTimeout: Duration
  ) async throws -> Data {
    do {
      try await transport.start(executable: executable)
      try await transport.send(.initialize)
      _ = try await transport.response(id: 0, timeout: startupTimeout)
      try await transport.send(.initialized)
      try await transport.send(message)
      let response = try await transport.response(id: id, timeout: requestTimeout)
      await transport.stop()
      return response
    } catch {
      await transport.stop()
      throw error
    }
  }
}

private actor JSONLResponseBuffer {
  private var partial = Data()
  private var lines: [Data] = []

  func append(_ data: Data) {
    partial.append(data)
    while let newline = partial.firstIndex(of: 0x0A) {
      let line = Data(partial[..<newline])
      partial.removeSubrange(...newline)
      if !line.isEmpty { lines.append(line) }
    }
  }

  func takeResponse(id: Int) -> Data? {
    guard
      let index = lines.firstIndex(where: { line in
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let number = object["id"] as? NSNumber
        else { return false }
        return number.intValue == id
      })
    else { return nil }
    return lines.remove(at: index)
  }

  func reset() {
    partial.removeAll(keepingCapacity: false)
    lines.removeAll(keepingCapacity: false)
  }
}

private actor BoundedTextBuffer {
  private let limit: Int
  private var data = Data()

  init(limit: Int) { self.limit = limit }

  func append(_ newData: Data) {
    data.append(newData)
    if data.count > limit {
      data.removeFirst(data.count - limit)
    }
  }

  func text() -> String {
    String(decoding: data, as: UTF8.self)
  }
}
