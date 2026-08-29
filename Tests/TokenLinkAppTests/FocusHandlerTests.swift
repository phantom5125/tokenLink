import Foundation
import Testing
import TokenLinkCore
import TokenLinkDevice

@testable import TokenLinkApp

private final class FakeActivator: CodexDesktopActivating, @unchecked Sendable {
  var canOpen = true
  var canActivate = true
  private(set) var openedThreadIDs: [String] = []
  private(set) var activations = 0

  func openCodexThread(_ threadID: String) -> Bool {
    openedThreadIDs.append(threadID)
    return canOpen
  }

  func activateCodexDesktop() -> Bool {
    activations += 1
    return canActivate
  }
}

private actor EventLog {
  private(set) var messages: [String] = []
  func append(_ message: String) {
    messages.append(message)
  }
}

@MainActor
private func makeHandler(
  sessions: [Int: FocusSession],
  activator: FakeActivator,
  log: EventLog,
  onRefresh: @escaping @Sendable () async -> Void = {}
) -> FocusHandler {
  FocusHandler(
    sessionProvider: { sessions[$0] },
    activator: activator,
    onRefresh: onRefresh,
    record: { message in await log.append(message) })
}

@MainActor @Test func focusOnCodexSlotOpensThreadWithoutLoggingThreadIdentifier() async {
  let activator = FakeActivator()
  let log = EventLog()
  let handler = makeHandler(
    sessions: [1: FocusSession(slot: 1, source: .codex, threadID: "thread-1")],
    activator: activator,
    log: log)

  await handler.handle(.focus(slot: 1))

  #expect(activator.openedThreadIDs == ["thread-1"])
  #expect(activator.activations == 0)
  let messages = await log.messages
  #expect(messages.contains("Watch focus opened Codex session"))
  #expect(!messages.contains { $0.contains("thread-1") })
}

@MainActor @Test func focusOnNonCodexSlotOnlyRecordsEvent() async {
  let activator = FakeActivator()
  let log = EventLog()
  let handler = makeHandler(
    sessions: [0: FocusSession(slot: 0, source: .kimi)],
    activator: activator,
    log: log)

  await handler.handle(.focus(slot: 0))

  #expect(activator.activations == 0)
  #expect(activator.openedThreadIDs.isEmpty)
  let messages = await log.messages
  #expect(messages.contains { $0.contains("not a Codex session") })
}

@MainActor @Test func focusOnEmptySlotOnlyRecordsEvent() async {
  let activator = FakeActivator()
  let log = EventLog()
  let handler = makeHandler(sessions: [:], activator: activator, log: log)

  await handler.handle(.focus(slot: 2))

  #expect(activator.activations == 0)
  #expect(activator.openedThreadIDs.isEmpty)
  let messages = await log.messages
  #expect(messages.contains { $0.contains("no work item in slot 2") })
}

@MainActor @Test func focusWhenDesktopUnavailableRecordsFailure() async {
  let activator = FakeActivator()
  activator.canOpen = false
  activator.canActivate = false
  let log = EventLog()
  let handler = makeHandler(
    sessions: [0: FocusSession(slot: 0, source: .codex, threadID: "thread-9")],
    activator: activator,
    log: log)

  await handler.handle(.focus(slot: 0))

  #expect(activator.openedThreadIDs == ["thread-9"])
  #expect(activator.activations == 1)
  let messages = await log.messages
  #expect(messages.contains { $0.contains("not running") })
}

@MainActor @Test func missingThreadIDFallsBackToDesktopActivation() async {
  let activator = FakeActivator()
  let log = EventLog()
  let handler = makeHandler(
    sessions: [0: FocusSession(slot: 0, source: .codex)],
    activator: activator,
    log: log)

  await handler.handle(.focus(slot: 0))

  #expect(activator.openedThreadIDs.isEmpty)
  #expect(activator.activations == 1)
  #expect(await log.messages.contains { $0.contains("session link unavailable") })
}

@MainActor @Test func refreshCommandTriggersRefreshCallback() async {
  let log = EventLog()
  final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
  }
  let counter = Counter()
  let handler = makeHandler(
    sessions: [:],
    activator: FakeActivator(),
    log: log,
    onRefresh: { counter.increment() })

  await handler.handle(.refresh)
  await handler.handle(.refresh)

  #expect(counter.value == 2)
}
