import Foundation
import Testing

@testable import TokenLinkDevice

private actor FakeBLETransport: BLETransport {
  nonisolated private let commandHub = AsyncEventHub<Data>()
  private let capabilities: WatchCapabilities?

  init(capabilities: WatchCapabilities? = WatchCapabilities(protocolVersions: [1, 2])) {
    self.capabilities = capabilities
  }

  func emitCommand(_ data: Data) {
    commandHub.yield(data)
  }

  func discoveredIdentifiers() async throws -> [UUID] { [] }
  func connect(identifier: UUID) async throws {}
  func writeWithResponse(_ data: Data) async throws {}
  func readCapabilities() async throws -> WatchCapabilities? { capabilities }
  func disconnect() async {}
  nonisolated func commandEvents() -> AsyncStream<Data> { commandHub.stream() }
}

private let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

@Test func decodesFocusAndRefreshCommands() {
  #expect(
    WatchCommand.decode(Data(#"{"action":"focus","slot":1}"#.utf8))
      == .focus(slot: 1))
  #expect(WatchCommand.decode(Data(#"{"action":"refresh"}"#.utf8)) == .refresh)
}

@Test func decodesCompactMtuSafeCommands() {
  #expect(
    WatchCommand.decode(Data(#"{"a":"f","s":1}"#.utf8))
      == .focus(slot: 1))
  #expect(WatchCommand.decode(Data(#"{"a":"r"}"#.utf8)) == .refresh)
}

@Test func decodeRejectsMalformedFrames() {
  #expect(WatchCommand.decode(Data("not json".utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{"action":"focus"}"#.utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{"action":"focus","slot":3}"#.utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{"action":"focus","slot":-1}"#.utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{"action":"focus","slot":"1"}"#.utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{"a":"f","s":3}"#.utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{"action":"explode"}"#.utf8)) == nil)
  #expect(WatchCommand.decode(Data(#"{}"#.utf8)) == nil)
}

@Test func bridgeForwardsCommandsAfterV2Negotiation() async throws {
  let transport = FakeBLETransport()
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  await bridge.startObservingTransport()
  try await bridge.connect()

  var iterator = bridge.commandStream.makeAsyncIterator()
  await transport.emitCommand(Data(#"{"action":"focus","slot":2}"#.utf8))
  await transport.emitCommand(Data(#"{"action":"refresh"}"#.utf8))

  #expect(await iterator.next() == .focus(slot: 2))
  #expect(await iterator.next() == .refresh)
  #expect(await bridge.droppedCommandCount == 0)
  await bridge.stopObservingTransport()
}

@Test func bridgeCountsAndDropsMalformedCommands() async throws {
  let transport = FakeBLETransport()
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  await bridge.startObservingTransport()
  try await bridge.connect()

  var iterator = bridge.commandStream.makeAsyncIterator()
  await transport.emitCommand(Data("garbage".utf8))
  await transport.emitCommand(Data(#"{"action":"focus","slot":9}"#.utf8))
  await transport.emitCommand(Data(#"{"action":"focus","slot":0}"#.utf8))

  #expect(await iterator.next() == .focus(slot: 0))
  #expect(await bridge.droppedCommandCount == 2)
  await bridge.stopObservingTransport()
}

@Test func bridgeIgnoresCommandChannelBeforeV2Negotiation() async throws {
  let transport = FakeBLETransport(
    capabilities: WatchCapabilities(protocolVersions: [1]))
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  await bridge.startObservingTransport()
  try await bridge.connect()

  let collector = Task {
    var commands: [WatchCommand] = []
    for await command in bridge.commandStream {
      commands.append(command)
    }
    return commands
  }
  await transport.emitCommand(Data(#"{"action":"focus","slot":0}"#.utf8))
  try? await Task.sleep(for: .milliseconds(50))
  collector.cancel()

  #expect(await collector.value == [])
  #expect(await bridge.droppedCommandCount == 0)
  await bridge.stopObservingTransport()
}

@Test func bridgeCommandObservationCanRestartAfterCancellation() async throws {
  let transport = FakeBLETransport()
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  await bridge.startObservingTransport()
  try await bridge.connect()

  var firstIterator = bridge.commandStream.makeAsyncIterator()
  await transport.emitCommand(Data(#"{"a":"f","s":0}"#.utf8))
  #expect(await firstIterator.next() == .focus(slot: 0))

  await bridge.stopObservingTransport()
  await bridge.startObservingTransport()
  await Task.yield()
  var replacementIterator = bridge.commandStream.makeAsyncIterator()
  await transport.emitCommand(Data(#"{"a":"f","s":1}"#.utf8))
  #expect(await replacementIterator.next() == .focus(slot: 1))
  await bridge.stopObservingTransport()
}
