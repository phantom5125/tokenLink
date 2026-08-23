import Foundation
import Testing

@testable import TokenLinkCore
@testable import TokenLinkDevice

private actor FakeBLETransport: BLETransport {
  let discovered: [UUID]
  private(set) var connectedIdentifiers: [UUID] = []
  private(set) var writtenPayloads: [Data] = []

  init(discovered: [UUID]) { self.discovered = discovered }

  func discoveredIdentifiers() async throws -> [UUID] { discovered }
  func connect(identifier: UUID) async throws { connectedIdentifiers.append(identifier) }
  func writeWithResponse(_ data: Data) async throws { writtenPayloads.append(data) }
  func disconnect() async {}
}

@Test func bridgeIgnoresUnboundPeripheralAndWritesBoundOne() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let transport = FakeBLETransport(discovered: [other, bound])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  try await bridge.connect()
  #expect(await transport.connectedIdentifiers == [bound])
}

@Test func unboundBridgeStaysUnboundAndSkipsScan() async throws {
  let transport = FakeBLETransport(discovered: [
    UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  ])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: nil)
  try await bridge.connect()
  #expect(await bridge.phase == .unbound)
  #expect(await transport.connectedIdentifiers.isEmpty)
}

@Test func syncWritesPayloadAndMarksSyncedPhase() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
  let transport = FakeBLETransport(discovered: [bound])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  try await bridge.connect()
  let now = Date(timeIntervalSince1970: 1_000)
  try await bridge.sync(Data("{}".utf8), now: now)
  #expect(await transport.writtenPayloads == [Data("{}".utf8)])
  #expect(await bridge.phase == .synced(now))
}
