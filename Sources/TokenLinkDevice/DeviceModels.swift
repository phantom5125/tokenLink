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

public protocol BLETransport: Sendable {
  func discoveredIdentifiers() async throws -> [UUID]
  func connect(identifier: UUID) async throws
  func writeWithResponse(_ data: Data) async throws
  func disconnect() async
}

public actor DeviceBridge {
  private let transport: any BLETransport
  private let boundIdentifier: UUID?
  public private(set) var phase: DevicePhase

  public init(transport: any BLETransport, boundIdentifier: UUID?) {
    self.transport = transport
    self.boundIdentifier = boundIdentifier
    self.phase = boundIdentifier == nil ? .unbound : .disconnected
  }

  public func connect() async throws {
    guard let boundIdentifier else { return }
    switch phase {
    case .connected, .syncing, .synced:
      return
    default:
      break
    }
    phase = .scanning
    do {
      guard try await transport.discoveredIdentifiers().contains(boundIdentifier) else {
        phase = .disconnected
        return
      }
      phase = .connecting
      try await transport.connect(identifier: boundIdentifier)
      phase = .connected
    } catch {
      phase = .disconnected
      throw error
    }
  }

  public func sync(_ data: Data, now: Date = .now) async throws {
    phase = .syncing
    do {
      try await transport.writeWithResponse(data)
      phase = .synced(now)
    } catch {
      phase = .stale
      throw error
    }
  }

  public func disconnect() async {
    await transport.disconnect()
    phase = boundIdentifier == nil ? .unbound : .disconnected
  }
}
