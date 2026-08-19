import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private actor FakeAppServerTransport: AppServerTransport {
  enum Mode: Sendable {
    case fixture(Data)
    case timeout
  }

  let mode: Mode
  private(set) var messages: [AppServerMessage] = []
  private(set) var stopped = false

  init(mode: Mode) { self.mode = mode }

  func start(executable: URL) async throws {}

  func send(_ message: AppServerMessage) async throws {
    messages.append(message)
  }

  func response(id: Int, timeout: Duration) async throws -> Data {
    switch mode {
    case .fixture(let data): data
    case .timeout: throw AppServerTransportError.timeout
    }
  }

  func stop() async { stopped = true }
}

@Test func parsesCurrentAndLegacyCodexRateLimits() throws {
  let now = Date(timeIntervalSince1970: 1_787_130_000)
  let current = try CodexRateLimitParser.parse(
    data: Fixture.load("codex-rate-limits.json"), fetchedAt: now)
  #expect(current.windows[0].remainingPercent == 82)
  let legacyData = Data(
    #"{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":32,"resetsAt":1787616000}}}}"#
      .utf8)
  let legacy = try CodexRateLimitParser.parse(data: legacyData, fetchedAt: now)
  #expect(legacy.windows[0].remainingPercent == 68)
}

@Test func codexProviderHandshakesBeforeQuotaAndStops() async throws {
  let transport = FakeAppServerTransport(
    mode: .fixture(try Fixture.load("codex-rate-limits.json")))
  let provider = CodexProvider(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport,
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  let snapshot = try await provider.fetch().get()

  #expect(snapshot.provider == .codex)
  #expect(
    await transport.messages == [
      .initialize,
      .initialized,
      .rateLimits(id: 1),
    ])
  #expect(await transport.stopped)
}

@Test func codexProviderMapsTimeoutAndAlwaysStops() async {
  let transport = FakeAppServerTransport(mode: .timeout)
  let provider = CodexProvider(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport)

  let result = await provider.fetch()

  guard case .failure(let failure) = result else {
    Issue.record("Expected timeout failure")
    return
  }
  #expect(failure.kind == .timeout)
  #expect(await transport.stopped)
}

@Test func appServerMessagesEncodeExactMethods() throws {
  let initialize = try #require(
    JSONSerialization.jsonObject(with: AppServerMessage.initialize.jsonLine()) as? [String: Any])
  #expect(initialize["method"] as? String == "initialize")
  #expect(initialize["id"] as? Int == 0)

  let limits = try #require(
    JSONSerialization.jsonObject(with: AppServerMessage.rateLimits(id: 7).jsonLine())
      as? [String: Any])
  #expect(limits["method"] as? String == "account/rateLimits/read")
  #expect(limits["id"] as? Int == 7)
}
