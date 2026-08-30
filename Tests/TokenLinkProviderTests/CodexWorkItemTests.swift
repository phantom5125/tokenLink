import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private actor FakeThreadListTransport: AppServerTransport {
  enum Event: Equatable, Sendable {
    case started
    case sent(AppServerMessage)
    case awaited(Int)
    case stopped
  }

  enum Mode: Sendable {
    case fixtures([Data])
    case timeout
  }

  let mode: Mode
  private(set) var events: [Event] = []
  private(set) var stopped = false

  init(mode: Mode) { self.mode = mode }

  func start(executable: URL) async throws {
    events.append(.started)
  }

  func send(_ message: AppServerMessage) async throws {
    events.append(.sent(message))
  }

  func response(id: Int, timeout: Duration) async throws -> Data {
    events.append(.awaited(id))
    switch mode {
    case .fixtures(let pages):
      if id == 0 { return Data(#"{"id":0,"result":{}}"#.utf8) }
      let index = id - 2
      guard pages.indices.contains(index) else {
        throw AppServerTransportError.malformedResponse
      }
      return pages[index]
    case .timeout: throw AppServerTransportError.timeout
    }
  }

  func stop() async {
    stopped = true
    events.append(.stopped)
  }
}

// Shape mirrors a real codex-cli 0.135.0 thread/list response, trimmed to
// the fields the parser reads.
private let threadListFixture = Data(
  #"""
  {"id":2,"result":{"data":[
    {"id":"t-1","preview":"checking ipv6 support","name":"Fix IPv6 host unreachable",
     "createdAt":1781789610,"updatedAt":1781790583,
     "status":{"type":"active","activeFlags":["waitingOnApproval"]},
     "turns":[{"id":"turn-1","status":"inProgress"}]},
    {"id":"t-2","preview":"daily inbox sweep","name":null,
     "createdAt":1781788620,"updatedAt":1781789071,
     "status":{"type":"notLoaded"},
     "turns":[]},
    {"id":"t-3","preview":"k8s yaml health workbench","name":"检查 IPv6 支持",
     "createdAt":1781788600,"updatedAt":1781789000,
     "status":{"type":"idle"},
     "turns":[{"id":"turn-1","status":"completed"},{"id":"turn-2","status":"interrupted"}]}
  ],"nextCursor":null,"backwardsCursor":null}}
  """#.utf8)

@Test func desktopCodexPrecedesPathUnlessUserConfiguredOne() {
  let automatic = CodexExecutableResolver.candidatePaths(
    configuredPath: nil,
    environmentPath: "/old/bin:/other/bin",
    homeDirectory: URL(filePath: "/Users/test"))
  #expect(automatic.first == "/Applications/Codex.app/Contents/Resources/codex")
  #expect(
    automatic.firstIndex(of: "/Applications/ChatGPT.app/Contents/Resources/codex")!
      < automatic.firstIndex(of: "/old/bin/codex")!)

  let explicit = CodexExecutableResolver.candidatePaths(
    configuredPath: "/chosen/codex",
    environmentPath: "/old/bin",
    homeDirectory: URL(filePath: "/Users/test"))
  #expect(explicit.first == "/chosen/codex")
}

@Test func stateMappingCoversAllBranches() {
  #expect(CodexWorkItemStateMapping.state(statusType: "active") == .running)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "active", activeFlags: ["paused"]) == .running)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "active", activeFlags: ["waitingOnApproval"])
      == .needsInput)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "active", activeFlags: ["waitingOnUserInput"])
      == .needsInput)
  #expect(CodexWorkItemStateMapping.state(statusType: "systemError") == .failed)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "idle", lastTurnStatus: "inProgress") == .running)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "idle", lastTurnStatus: "completed")
      == .completed)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "idle", lastTurnStatus: "interrupted") == .failed)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "idle", lastTurnStatus: "failed") == .failed)
  #expect(
    CodexWorkItemStateMapping.state(statusType: "notLoaded", lastTurnStatus: nil) == .unknown)
  #expect(CodexWorkItemStateMapping.state(statusType: "surprise") == .unknown)
}

@Test func threadListParserMapsThreadsToSnapshots() throws {
  let threads = try CodexThreadListParser.parse(data: threadListFixture)
  #expect(threads.count == 3)

  #expect(threads[0].id == "t-1")
  #expect(threads[0].name == "Fix IPv6 hos")  // 12 ASCII chars
  #expect(threads[0].state == .needsInput)
  #expect(threads[0].updatedAt == Date(timeIntervalSince1970: 1_781_790_583))

  #expect(threads[1].name == "daily inbox")  // preview first line, truncated
  #expect(threads[1].state == .unknown)

  #expect(threads[2].name == "IPv6")  // non-ASCII filtered out
  #expect(threads[2].state == .failed)  // last turn interrupted
}

@Test func parserUsesWorkspaceWhenTitleHasNoPrintableASCII() throws {
  let fixture = Data(
    #"{"id":2,"result":{"data":[{"id":"t","name":"检查表盘","preview":null,"cwd":"/Users/test/tokenLink","path":null,"updatedAt":100,"status":{"type":"notLoaded"},"turns":[]}]}}"#
      .utf8)
  let threads = try CodexThreadListParser.parse(data: fixture)
  #expect(threads.first?.name == "tokenLink")
}

@Test func parserUsesFreshRolloutLifecycleForDesktopOwnedThread() throws {
  let fixture = Data(
    #"{"id":2,"result":{"data":[{"id":"t","name":"watch","preview":null,"cwd":"/tmp/tokenLink","path":"/trusted/live.jsonl","updatedAt":100,"status":{"type":"notLoaded"},"turns":[]}]}}"#
      .utf8)
  let threads = try CodexThreadListParser.parse(data: fixture) { path in
    path == "/trusted/live.jsonl" ? .running : nil
  }
  #expect(threads.first?.state == .running)

  let completed = try CodexThreadListParser.parse(data: fixture) { path in
    path == "/trusted/live.jsonl" ? .completed : nil
  }
  #expect(completed.first?.state == .completed)
}

@Test func rolloutReaderRecognizesOnlyFreshUnfinishedTurns() throws {
  let root = FileManager.default.temporaryDirectory
    .appending(path: "tokenlink-rollout-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let file = root.appending(path: "live.jsonl")
  let started = #"{"type":"event_msg","payload":{"type":"task_started"}}"#
  try Data((started + "\n").utf8).write(to: file)
  #expect(CodexRolloutActivityReader.state(atPath: file.path, allowedRoot: root) == .running)

  let complete = #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
  try Data((started + "\n" + complete + "\n").utf8).write(to: file)
  #expect(CodexRolloutActivityReader.state(atPath: file.path, allowedRoot: root) == .completed)

  let aborted = #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#
  try Data((started + "\n" + aborted + "\n").utf8).write(to: file)
  #expect(CodexRolloutActivityReader.state(atPath: file.path, allowedRoot: root) == .failed)

  let nonLifecycle = #"{"type":"response_item","payload":{"type":"tool_output"}}"#
  let longRunning = started + "\n" + String(repeating: nonLifecycle + "\n", count: 6_000)
  try Data(longRunning.utf8).write(to: file)
  #expect(CodexRolloutActivityReader.state(atPath: file.path, allowedRoot: root) == .running)
}

@Test func rolloutReaderRejectsSymlinksEscapingTheAllowedRoot() throws {
  let sandbox = FileManager.default.temporaryDirectory
    .appending(path: "tokenlink-rollout-symlink-\(UUID().uuidString)")
  let root = sandbox.appending(path: "allowed")
  let outside = sandbox.appending(path: "outside.jsonl")
  let link = root.appending(path: "escaped.jsonl")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: sandbox) }
  try Data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8)
    .write(to: outside)
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

  #expect(CodexRolloutActivityReader.state(atPath: link.path, allowedRoot: root) == nil)
}

@Test func threadListParserRejectsMalformedPayloads() {
  #expect(throws: DecodingError.self) {
    _ = try CodexThreadListParser.parse(
      data: Data(#"{"id":2,"result":{"data":[{"id":"x"}]}}"#.utf8))
  }
  #expect(throws: CodexThreadListParseError.missingResult) {
    _ = try CodexThreadListParser.parse(data: Data(#"{"id":2,"error":{"code":-32601}}"#.utf8))
  }
}

@Test func trackerHandshakesBeforeListingThreads() async throws {
  let transport = FakeThreadListTransport(mode: .fixtures([threadListFixture]))
  let tracker = CodexWorkItemTracker(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport)

  let result = await tracker.fetchThreads()

  let threads = try result.get()
  #expect(threads.count == 3)
  #expect(
    await transport.events == [
      .started,
      .sent(.initialize),
      .awaited(0),
      .sent(.initialized),
      .sent(.threadList(id: 2, limit: 50, cursor: nil)),
      .awaited(2),
      .stopped,
    ])
}

@Test func trackerPaginatesAndDeduplicatesBeforeCountingActiveSessions() async throws {
  let firstPage = Data(
    #"{"id":2,"result":{"data":[{"id":"running","name":"run","updatedAt":100,"status":{"type":"active"},"turns":[]}],"nextCursor":"page-2"}}"#
      .utf8)
  let secondPage = Data(
    #"{"id":3,"result":{"data":[{"id":"running","name":"run-new","updatedAt":200,"status":{"type":"active"},"turns":[]},{"id":"approval","name":"approval","updatedAt":150,"status":{"type":"active","activeFlags":["waitingOnApproval"]},"turns":[]}],"nextCursor":null}}"#
      .utf8)
  let transport = FakeThreadListTransport(mode: .fixtures([firstPage, secondPage]))
  let tracker = CodexWorkItemTracker(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport)

  let result = await tracker.fetchThreads()

  let threads = try result.get()
  #expect(threads.count == 2)
  #expect(
    threads.first(where: { $0.id == "running" })?.updatedAt
      == Date(timeIntervalSince1970: 200))
  #expect(
    await transport.events == [
      .started,
      .sent(.initialize),
      .awaited(0),
      .sent(.initialized),
      .sent(.threadList(id: 2, limit: 50, cursor: nil)),
      .awaited(2),
      .sent(.threadList(id: 3, limit: 50, cursor: "page-2")),
      .awaited(3),
      .stopped,
    ])
}

@Test func trackerMapsTimeoutAndAlwaysStops() async {
  let transport = FakeThreadListTransport(mode: .timeout)
  let tracker = CodexWorkItemTracker(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport)

  let result = await tracker.fetchThreads()

  guard case .failure(let failure) = result else {
    Issue.record("Expected timeout failure")
    return
  }
  #expect(failure.kind == .timeout)
  #expect(await transport.stopped)
}

@Test func trackerRejectsIncompletePaginationAndAlwaysStops() async {
  let unfinishedPage = Data(
    #"{"id":2,"result":{"data":[],"nextCursor":"more"}}"#.utf8)
  let transport = FakeThreadListTransport(mode: .fixtures([unfinishedPage]))
  let tracker = CodexWorkItemTracker(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport,
    maxThreadPages: 1)

  let result = await tracker.fetchThreads()

  guard case .failure(let failure) = result else {
    Issue.record("Expected bounded pagination failure")
    return
  }
  #expect(failure.kind == .decoding)
  #expect(await transport.stopped)
}

@Test func trackerPollUpsertsIntoStore() async throws {
  let transport = FakeThreadListTransport(mode: .fixtures([threadListFixture]))
  let tracker = CodexWorkItemTracker(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport)
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "archived", name: "archived", source: .codex, state: .completed,
    updatedAt: Date(timeIntervalSince1970: 10))

  let failure = await tracker.poll(into: store)

  #expect(failure == nil)
  let items = await store.items
  #expect(items.count == 3)
  #expect(!items.contains(where: { $0.id == "archived" }))
  #expect(items.map(\.source) == [.codex, .codex, .codex])
  #expect(items.map(\.state) == [.needsInput, .unknown, .failed])
  #expect(await store.activeSessionCount == 1)
}

@Test func trackerPollLeavesStoreUntouchedOnFailure() async {
  let transport = FakeThreadListTransport(mode: .timeout)
  let tracker = CodexWorkItemTracker(
    executable: URL(filePath: "/usr/bin/true"),
    transport: transport)
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "keep", name: "keep", source: .codex, state: .running,
    updatedAt: Date(timeIntervalSince1970: 100))

  let failure = await tracker.poll(into: store)

  #expect(failure?.kind == .timeout)
  #expect(await store.items.map(\.id) == ["keep"])
}
