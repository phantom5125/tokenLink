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

public protocol BLETransport: Sendable {
  func discoveredIdentifiers() async throws -> [UUID]
  func connect(identifier: UUID) async throws
  func writeWithResponse(_ data: Data) async throws
  func disconnect() async
  func connectionEvents() -> AsyncStream<BLETransportEvent>
}

extension BLETransport {
  public func connectionEvents() -> AsyncStream<BLETransportEvent> {
    AsyncStream { continuation in continuation.finish() }
  }
}

public actor DeviceBridge {
  nonisolated private let phaseStream: AsyncStream<DevicePhase>
  nonisolated private let phaseContinuation: AsyncStream<DevicePhase>.Continuation
  private let transport: any BLETransport
  private let boundIdentifier: UUID?
  private let connectTimeout: Duration
  private let writeTimeout: Duration
  private var transportEventTask: Task<Void, Never>?
  public private(set) var phase: DevicePhase

  public init(
    transport: any BLETransport,
    boundIdentifier: UUID?,
    connectTimeout: Duration = .seconds(12),
    writeTimeout: Duration = .seconds(7)
  ) {
    (phaseStream, phaseContinuation) = AsyncStream.makeStream(
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
  }

  public func stopObservingTransport() {
    transportEventTask?.cancel()
    transportEventTask = nil
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
      updatePhase(boundIdentifier == nil ? .unbound : .disconnected)
    }
  }

  private func updatePhase(_ replacement: DevicePhase) {
    phase = replacement
    phaseContinuation.yield(replacement)
  }

  private static func perform(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> Void
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
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
