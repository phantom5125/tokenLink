import Foundation
import Testing

@testable import TokenLinkCore
@testable import TokenLinkProviders

@Test func parsesCurrentAndLegacyCodexRateLimits() throws {
  let now = Date(timeIntervalSince1970: 1_787_130_000)
  let current = try CodexRateLimitParser.parse(
    data: Fixture.load("codex-rate-limits.json"),
    fetchedAt: now)
  #expect(current.windows[0].remainingPercent == 82)
  let legacyData = Data(
    #"{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":32,"resetsAt":1787616000}}}}"#
      .utf8)
  let legacy = try CodexRateLimitParser.parse(data: legacyData, fetchedAt: now)
  #expect(legacy.windows[0].remainingPercent == 68)
}

private actor FakeAppServerTransport: AppServerTransport {
  enum Mode {
    case success(Data)
    case timeout, throwMissingExecutable
  }
  private var mode: Mode
  private(set) var sentMessages: [AppServerMessage] = []
  private(set) var startedExecutable: URL?
  private(set) var stopCount = 0

  init(mode: Mode) { self.mode = mode }

  func start(executable: URL) async throws {
    if case .throwMissingExecutable = mode {
      throw AppServerClientError.missingExecutable
    }
    startedExecutable = executable
  }

  func send(_ message: AppServerMessage) async throws {
    sentMessages.append(message)
  }

  func response(id: Int, timeout: Duration) async throws -> Data {
    switch mode {
    case .success(let data):
      return data
    case .timeout:
      try await Task.sleep(for: timeout)
      throw AppServerClientError.timeout
    case .throwMissingExecutable:
      throw AppServerClientError.missingExecutable
    }
  }

  func stop() async {
    stopCount += 1
  }
}

@Test func codexProviderSendsInitializeBeforeQuota() async throws {
  let transport = FakeAppServerTransport(
    mode: .success(try Fixture.load("codex-rate-limits.json")))
  let provider = CodexProvider(
    executable: URL(fileURLWithPath: "/usr/bin/true"),
    transport: transport,
    timeout: .seconds(2))
  let result = await provider.fetch()
  _ = try result.get()
  let sent = await transport.sentMessages
  #expect(sent == [.initialize, .initialized, .rateLimits(id: 1)])
  let stopCount = await transport.stopCount
  #expect(stopCount == 1)
}

@Test func codexProviderMapsTimeoutToFailure() async {
  let transport = FakeAppServerTransport(mode: .timeout)
  let provider = CodexProvider(
    executable: URL(fileURLWithPath: "/usr/bin/true"),
    transport: transport,
    timeout: .milliseconds(50))
  let result = await provider.fetch()
  switch result {
  case .success: Issue.record("expected timeout failure")
  case .failure(let failure):
    #expect(failure.kind == .timeout)
  }
  let stopCount = await transport.stopCount
  #expect(stopCount == 1)
}

@Test func codexProviderReportsMissingExecutable() async {
  let transport = FakeAppServerTransport(mode: .throwMissingExecutable)
  let provider = CodexProvider(
    executable: URL(fileURLWithPath: "/definitely/not/a/real/path/codex"),
    transport: transport,
    timeout: .milliseconds(50))
  let result = await provider.fetch()
  switch result {
  case .success: Issue.record("expected missingExecutable failure")
  case .failure(let failure):
    #expect(failure.kind == .missingCredential)
  }
  let stopCount = await transport.stopCount
  #expect(stopCount == 1)
}
