import Foundation
import Testing

@testable import TokenLinkDevice

private actor FakeBLETransport: BLETransport {
  let discovered: [UUID]
  private(set) var connectedIdentifiers: [UUID] = []
  private(set) var writes: [Data] = []
  private(set) var disconnected = false

  init(discovered: [UUID]) { self.discovered = discovered }

  func discoveredIdentifiers() async throws -> [UUID] { discovered }
  func connect(identifier: UUID) async throws { connectedIdentifiers.append(identifier) }
  func writeWithResponse(_ data: Data) async throws { writes.append(data) }
  func disconnect() async { disconnected = true }
}

@Test func bridgeIgnoresUnboundPeripheralAndWritesBoundOne() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let transport = FakeBLETransport(discovered: [other, bound])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()
  try await bridge.sync(Data("quota".utf8), now: Date(timeIntervalSince1970: 10))

  #expect(await transport.connectedIdentifiers == [bound])
  #expect(await transport.writes == [Data("quota".utf8)])
  #expect(await bridge.phase == .synced(Date(timeIntervalSince1970: 10)))
}

@Test func bridgeStaysDisconnectedWhenBoundDeviceIsNotDiscovered() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = FakeBLETransport(discovered: [])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()

  #expect(await transport.connectedIdentifiers.isEmpty)
  #expect(await bridge.phase == .disconnected)
}

@Test func bridgeWithoutBindingDoesNotScan() async throws {
  let transport = FakeBLETransport(discovered: [])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: nil)

  try await bridge.connect()

  #expect(await bridge.phase == .unbound)
}
