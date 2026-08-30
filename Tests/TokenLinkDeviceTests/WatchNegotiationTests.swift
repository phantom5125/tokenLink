import Foundation
import Testing

@testable import TokenLinkDevice

private actor FakeBLETransport: BLETransport {
  private var capabilities: WatchCapabilities?
  private var capabilitiesError: (any Error)?
  private(set) var readCapabilitiesCalls = 0
  private(set) var connectCount = 0
  private(set) var writes: [Data] = []

  init(capabilities: WatchCapabilities? = nil, capabilitiesError: (any Error)? = nil) {
    self.capabilities = capabilities
    self.capabilitiesError = capabilitiesError
  }

  func setCapabilities(_ value: WatchCapabilities?) {
    capabilities = value
    capabilitiesError = nil
  }

  func discoveredIdentifiers() async throws -> [UUID] { [] }
  func connect(identifier: UUID) async throws {
    connectCount += 1
  }
  func writeWithResponse(_ data: Data) async throws {
    writes.append(data)
  }
  func readCapabilities() async throws -> WatchCapabilities? {
    readCapabilitiesCalls += 1
    if let capabilitiesError { throw capabilitiesError }
    return capabilities
  }
  func disconnect() async {}
}

/// A transport written against the v1 protocol surface: it does not implement
/// `readCapabilities()` or `commandEvents()` at all. It must keep compiling
/// and behaving as a v1-only device.
private struct LegacyFakeTransport: BLETransport {
  func discoveredIdentifiers() async throws -> [UUID] { [] }
  func connect(identifier: UUID) async throws {}
  func writeWithResponse(_ data: Data) async throws {}
  func disconnect() async {}
}

private let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

@Test func legacyCapabilitiesDecodeWithEmptyOptionalFeatures() throws {
  let data = Data(
    #"{"protocol_versions":[1,2],"firmware":"0.2.1-tokenlink"}"#.utf8)

  let capabilities = try JSONDecoder().decode(WatchCapabilities.self, from: data)

  #expect(capabilities.protocolVersions == [1, 2])
  #expect(capabilities.features.isEmpty)
  #expect(capabilities.faceRuntimeVersions.isEmpty)
  #expect(!capabilities.supports(.faceRuntime))
  #expect(!capabilities.supportsFaceRuntime(version: 1))
}

@Test func capabilitiesPreserveKnownAndFutureFaceFeatures() throws {
  let data = Data(
    #"{"protocol_versions":[1,2],"firmware":"0.3.0-tokenlink","features":["face_runtime","future_feature"],"face_runtime_versions":[1],"face_asset_formats":["rgb565"],"max_face_package_bytes":262144}"#
      .utf8)

  let capabilities = try JSONDecoder().decode(WatchCapabilities.self, from: data)

  #expect(capabilities.supports(.faceRuntime))
  #expect(capabilities.supportsFaceRuntime(version: 1))
  #expect(!capabilities.supports(.facePackages))
  #expect(capabilities.features.contains("future_feature"))
  #expect(capabilities.faceAssetFormats == ["rgb565"])
  #expect(capabilities.maximumFacePackageBytes == 262_144)
}

@Test func bridgeNegotiatesV2WhenFirmwareSupportsIt() async throws {
  let capabilities = WatchCapabilities(protocolVersions: [1, 2], firmware: "0.2.0")
  let transport = FakeBLETransport(capabilities: capabilities)
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()

  #expect(await bridge.negotiatedProtocol == .v2(capabilities))
  #expect(await transport.readCapabilitiesCalls == 1)
}

@Test func bridgeFallsBackToV1WhenFirmwareLacksV2() async throws {
  let transport = FakeBLETransport(
    capabilities: WatchCapabilities(protocolVersions: [1], firmware: "0.1.0"))
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()

  #expect(await bridge.negotiatedProtocol == .v1)
  #expect(await bridge.phase == .connected)
}

@Test func bridgeFallsBackToV1WhenCapabilitiesReadFails() async throws {
  let transport = FakeBLETransport(
    capabilitiesError: BluetoothTransportError.characteristicNotFound)
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()

  #expect(await bridge.negotiatedProtocol == .v1)
  #expect(await bridge.phase == .connected)
}

@Test func legacyTransportWithoutCapabilitiesSupportStaysV1() async throws {
  let bridge = DeviceBridge(
    transport: LegacyFakeTransport(), boundIdentifier: bound)

  try await bridge.connect()
  try await bridge.sync(Data("quota".utf8))

  #expect(await bridge.negotiatedProtocol == .v1)
}

@Test func negotiationIsCachedForTheConnectionLifetime() async throws {
  let capabilities = WatchCapabilities(protocolVersions: [2])
  let transport = FakeBLETransport(capabilities: capabilities)
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()
  try await bridge.sync(Data("one".utf8))
  try await bridge.connect()
  try await bridge.sync(Data("two".utf8))

  #expect(await transport.readCapabilitiesCalls == 1)
  #expect(await transport.connectCount == 1)
  #expect(await bridge.negotiatedProtocol == .v2(capabilities))
}

@Test func negotiationRepeatsAfterExplicitDisconnect() async throws {
  let capabilities = WatchCapabilities(protocolVersions: [2])
  let transport = FakeBLETransport(capabilities: capabilities)
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)

  try await bridge.connect()
  #expect(await bridge.negotiatedProtocol == .v2(capabilities))

  await bridge.disconnect()
  #expect(await bridge.negotiatedProtocol == .v1)

  await transport.setCapabilities(nil)
  try await bridge.connect()
  #expect(await bridge.negotiatedProtocol == .v1)
  #expect(await transport.readCapabilitiesCalls == 2)
}

@Test func unsolicitedDisconnectResetsNegotiation() async throws {
  final class EventBox: @unchecked Sendable {
    let stream: AsyncStream<BLETransportEvent>
    let continuation: AsyncStream<BLETransportEvent>.Continuation
    init() {
      (stream, continuation) = AsyncStream.makeStream(
        bufferingPolicy: .bufferingNewest(8))
    }
  }
  actor EventedTransport: BLETransport {
    nonisolated let events = EventBox()
    private(set) var readCapabilitiesCalls = 0
    func discoveredIdentifiers() async throws -> [UUID] { [] }
    func connect(identifier: UUID) async throws {}
    func writeWithResponse(_ data: Data) async throws {}
    func readCapabilities() async throws -> WatchCapabilities? {
      readCapabilitiesCalls += 1
      return WatchCapabilities(protocolVersions: [1, 2])
    }
    func disconnect() async {}
    nonisolated func connectionEvents() -> AsyncStream<BLETransportEvent> {
      events.stream
    }
  }

  let transport = EventedTransport()
  let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
  await bridge.startObservingTransport()
  try await bridge.connect()
  #expect(await bridge.negotiatedProtocol != .v1)

  transport.events.continuation.yield(.disconnected(bound))
  try? await Task.sleep(for: .milliseconds(20))

  #expect(await bridge.negotiatedProtocol == .v1)
  try await bridge.connect()
  #expect(await transport.readCapabilitiesCalls == 2)
  await bridge.stopObservingTransport()
}
