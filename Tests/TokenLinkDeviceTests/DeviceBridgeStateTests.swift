import Foundation
import Testing

@testable import TokenLinkDevice

private actor FakeBLETransport: BLETransport {
  nonisolated let eventStream: AsyncStream<BLETransportEvent>
  nonisolated let eventContinuation: AsyncStream<BLETransportEvent>.Continuation
  let discovered: [UUID]
  let connectDelay: Duration?
  let writeDelay: Duration?
  private(set) var connectedIdentifiers: [UUID] = []
  private(set) var writes: [Data] = []
  private(set) var disconnected = false

  init(
    discovered: [UUID],
    connectDelay: Duration? = nil,
    writeDelay: Duration? = nil
  ) {
    (eventStream, eventContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
    self.discovered = discovered
    self.connectDelay = connectDelay
    self.writeDelay = writeDelay
  }

  func discoveredIdentifiers() async throws -> [UUID] { discovered }
  func connect(identifier: UUID) async throws {
    if let connectDelay { try await Task.sleep(for: connectDelay) }
    connectedIdentifiers.append(identifier)
  }
  func writeWithResponse(_ data: Data) async throws {
    if let writeDelay { try await Task.sleep(for: writeDelay) }
    writes.append(data)
  }
  func disconnect() async {
    disconnected = true
    eventContinuation.yield(.disconnected(nil))
  }
  nonisolated func connectionEvents() -> AsyncStream<BLETransportEvent> { eventStream }
  func emit(_ event: BLETransportEvent) { eventContinuation.yield(event) }
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

@Test func bridgeConnectsPinnedDeviceWithoutDependingOnAdvertising() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = FakeBLETransport(discovered: [])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()

  #expect(await transport.connectedIdentifiers == [bound])
  #expect(await bridge.phase == .connected)
}

@Test func bridgeWithoutBindingDoesNotScan() async throws {
  let transport = FakeBLETransport(discovered: [])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: nil)

  try await bridge.connect()

  #expect(await bridge.phase == .unbound)
}

@Test func bridgeDoesNotReconnectAfterSuccessfulSync() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = FakeBLETransport(discovered: [bound])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()
  try await bridge.sync(Data("first".utf8))
  try await bridge.connect()

  #expect(await transport.connectedIdentifiers == [bound])
}

@Test func discoveryFilterAcceptsOnlyStopWatchSignatures() {
  #expect(
    StopWatchDiscoveryFilter.isCandidate(
      name: "Codex Micro",
      serviceUUIDs: []))
  #expect(
    StopWatchDiscoveryFilter.isCandidate(
      name: nil,
      serviceUUIDs: ["7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01"]))
  #expect(
    !StopWatchDiscoveryFilter.isCandidate(
      name: "Other Keyboard",
      serviceUUIDs: ["1812"]))
}

@Test func coreBluetoothManagerIsDeferredUntilExplicitDeviceAction() {
  let transport = CoreBluetoothTransport()
  #expect(!transport.hasInitializedCentralManager)
}

@Test func bridgeBoundsConnectAndWriteOperations() async {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let slowConnect = FakeBLETransport(
    discovered: [],
    connectDelay: .seconds(1))
  let connectBridge = DeviceBridge(
    transport: slowConnect,
    boundIdentifier: bound,
    connectTimeout: .milliseconds(10),
    writeTimeout: .milliseconds(10))

  await #expect(throws: BluetoothTransportError.timeout) {
    try await connectBridge.connect()
  }
  #expect(await connectBridge.phase == .disconnected)

  let slowWrite = FakeBLETransport(
    discovered: [],
    writeDelay: .seconds(1))
  let writeBridge = DeviceBridge(
    transport: slowWrite,
    boundIdentifier: bound,
    connectTimeout: .milliseconds(10),
    writeTimeout: .milliseconds(10))
  try? await writeBridge.connect()
  await #expect(throws: BluetoothTransportError.timeout) {
    try await writeBridge.sync(Data("quota".utf8))
  }
  #expect(await writeBridge.phase == .stale)
}

@Test func bridgeOwnsUnsolicitedDisconnectState() async throws {
  let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let transport = FakeBLETransport(discovered: [])
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  await bridge.startObservingTransport()
  try await bridge.connect()
  try await bridge.sync(Data("quota".utf8))

  await transport.emit(.disconnected(bound))
  try? await Task.sleep(for: .milliseconds(10))

  #expect(await bridge.phase == .disconnected)
  try await bridge.connect()
  #expect(await transport.connectedIdentifiers == [bound, bound])
  await bridge.stopObservingTransport()
}
