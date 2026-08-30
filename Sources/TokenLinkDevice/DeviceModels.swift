import Foundation

public enum DevicePhase: Equatable, Sendable {
  case unbound
  case disconnected
  case scanning
  case connecting
  case connected
  case syncing
  case synced(Date)
  case stale
}

public enum BLETransportEvent: Equatable, Sendable {
  case connected(UUID)
  case disconnected(UUID?)
}

public enum BluetoothAuthorizationState: String, Equatable, Sendable {
  case notDetermined
  case restricted
  case denied
  case allowed
  case unavailable
}

public enum BluetoothCentralState: String, Equatable, Sendable {
  case notInitialized
  case unknown
  case resetting
  case unsupported
  case unauthorized
  case poweredOff
  case poweredOn
}

public enum BluetoothConnectionStep: String, Equatable, Sendable {
  case idle
  case scanning
  case waitingForPower
  case connecting
  case discoveringServices
  case discoveringCharacteristics
  case subscribingCommands
  case ready
}

/// A credential-free, payload-free view of the CoreBluetooth state machine.
/// It is safe to include in exported diagnostics.
public struct BluetoothDiagnosticSnapshot: Equatable, Sendable {
  public let authorization: BluetoothAuthorizationState
  public let centralState: BluetoothCentralState
  public let connectionStep: BluetoothConnectionStep
  public let connectedIdentifier: UUID?
  public let quotaCharacteristicAvailable: Bool
  public let capabilitiesCharacteristicAvailable: Bool
  public let commandCharacteristicAvailable: Bool
  public let commandNotificationsActive: Bool

  public init(
    authorization: BluetoothAuthorizationState = .unavailable,
    centralState: BluetoothCentralState = .notInitialized,
    connectionStep: BluetoothConnectionStep = .idle,
    connectedIdentifier: UUID? = nil,
    quotaCharacteristicAvailable: Bool = false,
    capabilitiesCharacteristicAvailable: Bool = false,
    commandCharacteristicAvailable: Bool = false,
    commandNotificationsActive: Bool = false
  ) {
    self.authorization = authorization
    self.centralState = centralState
    self.connectionStep = connectionStep
    self.connectedIdentifier = connectedIdentifier
    self.quotaCharacteristicAvailable = quotaCharacteristicAvailable
    self.capabilitiesCharacteristicAvailable = capabilitiesCharacteristicAvailable
    self.commandCharacteristicAvailable = commandCharacteristicAvailable
    self.commandNotificationsActive = commandNotificationsActive
  }
}

public protocol BLETransport: Sendable {
  func discoveredIdentifiers() async throws -> [UUID]
  func connect(identifier: UUID) async throws
  func writeWithResponse(_ data: Data) async throws
  /// Reads firmware capabilities; nil (or a thrown error) means v1-only.
  func readCapabilities() async throws -> WatchCapabilities?
  /// Raw command frames the watch notifies on the command characteristic.
  func commandEvents() -> AsyncStream<Data>
  func disconnect() async
  func connectionEvents() -> AsyncStream<BLETransportEvent>
  func diagnosticSnapshot() async -> BluetoothDiagnosticSnapshot
}

extension BLETransport {
  public func connectionEvents() -> AsyncStream<BLETransportEvent> {
    AsyncStream { continuation in continuation.finish() }
  }

  /// Default for v1-only transports: no capabilities characteristic.
  public func readCapabilities() async throws -> WatchCapabilities? { nil }

  /// Default for v1-only transports: no command channel.
  public func commandEvents() -> AsyncStream<Data> {
    AsyncStream { continuation in continuation.finish() }
  }

  public func diagnosticSnapshot() async -> BluetoothDiagnosticSnapshot {
    BluetoothDiagnosticSnapshot()
  }
}

public actor DeviceBridge {
  nonisolated private let phaseStream: AsyncStream<DevicePhase>
  nonisolated private let phaseContinuation: AsyncStream<DevicePhase>.Continuation
  /// Watch → Mac commands; only populated after negotiating protocol v2.
  public nonisolated let commandStream: AsyncStream<WatchCommand>
  nonisolated private let commandContinuation: AsyncStream<WatchCommand>.Continuation
  private let transport: any BLETransport
  private let boundIdentifier: UUID?
  private let connectTimeout: Duration
  private let writeTimeout: Duration
  private var transportEventTask: Task<Void, Never>?
  private var commandEventTask: Task<Void, Never>?
  public private(set) var phase: DevicePhase
  /// Negotiated protocol for the current connection; reset on disconnect.
  public private(set) var negotiatedProtocol: NegotiatedProtocol = .v1
  /// Malformed command frames dropped since launch (diagnostics only).
  public private(set) var droppedCommandCount = 0

  public init(
    transport: any BLETransport,
    boundIdentifier: UUID?,
    connectTimeout: Duration = .seconds(12),
    writeTimeout: Duration = .seconds(7)
  ) {
    (phaseStream, phaseContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
    (commandStream, commandContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
    self.transport = transport
    self.boundIdentifier = boundIdentifier
    self.connectTimeout = connectTimeout
    self.writeTimeout = writeTimeout
    self.phase = boundIdentifier == nil ? .unbound : .disconnected
  }

  public nonisolated func phaseEvents() -> AsyncStream<DevicePhase> {
    phaseStream
  }

  public func startObservingTransport() {
    guard transportEventTask == nil else { return }
    let transport = transport
    transportEventTask = Task { [weak self] in
      for await event in transport.connectionEvents() {
        guard !Task.isCancelled, let self else { return }
        await self.handle(event)
      }
    }
    commandEventTask = Task { [weak self] in
      for await data in transport.commandEvents() {
        guard !Task.isCancelled, let self else { return }
        await self.handleCommand(data)
      }
    }
  }

  public func stopObservingTransport() {
    transportEventTask?.cancel()
    transportEventTask = nil
    commandEventTask?.cancel()
    commandEventTask = nil
  }

  public func connect() async throws {
    guard let boundIdentifier else { return }
    switch phase {
    case .connected, .syncing, .synced:
      return
    default:
      break
    }
    updatePhase(.connecting)
    do {
      let transport = transport
      try await Self.perform(timeout: connectTimeout) {
        try await transport.connect(identifier: boundIdentifier)
      }
      negotiatedProtocol = await Self.negotiate(
        transport: transport, timeout: writeTimeout)
      updatePhase(.connected)
    } catch {
      updatePhase(.disconnected)
      throw error
    }
  }

  public func sync(_ data: Data, now: Date = .now) async throws {
    updatePhase(.syncing)
    do {
      let transport = transport
      try await Self.perform(timeout: writeTimeout) {
        try await transport.writeWithResponse(data)
      }
      updatePhase(.synced(now))
    } catch {
      if phase != .disconnected {
        updatePhase(.stale)
      }
      throw error
    }
  }

  public func disconnect() async {
    await transport.disconnect()
    negotiatedProtocol = .v1
    updatePhase(boundIdentifier == nil ? .unbound : .disconnected)
  }

  private func handle(_ event: BLETransportEvent) {
    switch event {
    case .connected(let identifier):
      guard identifier == boundIdentifier else { return }
      switch phase {
      case .connecting, .disconnected:
        updatePhase(.connected)
      default:
        break
      }
    case .disconnected(let identifier):
      guard identifier == nil || identifier == boundIdentifier else { return }
      negotiatedProtocol = .v1
      updatePhase(boundIdentifier == nil ? .unbound : .disconnected)
    }
  }

  private func handleCommand(_ data: Data) {
    // The command channel only exists once v2 is negotiated; anything else is
    // ignored silently.
    guard case .v2 = negotiatedProtocol else { return }
    guard let command = WatchCommand.decode(data) else {
      droppedCommandCount += 1
      return
    }
    commandContinuation.yield(command)
  }

  /// Reads firmware capabilities; every failure path falls back to v1 so a
  /// v1-only watch (or a flaky read) never breaks sync.
  private static func negotiate(
    transport: any BLETransport,
    timeout: Duration
  ) async -> NegotiatedProtocol {
    guard
      let capabilities = try? await Self.perform(
        timeout: timeout,
        operation: {
          try await transport.readCapabilities()
        }),
      capabilities.protocolVersions.contains(WatchPayloadV2.protocolVersion)
    else { return .v1 }
    return .v2(capabilities)
  }

  private func updatePhase(_ replacement: DevicePhase) {
    phase = replacement
    phaseContinuation.yield(replacement)
  }

  private static func perform<T: Sendable>(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask(operation: operation)
      group.addTask {
        try await Task.sleep(for: timeout)
        throw BluetoothTransportError.timeout
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else {
        throw BluetoothTransportError.timeout
      }
      return result
    }
  }
}
