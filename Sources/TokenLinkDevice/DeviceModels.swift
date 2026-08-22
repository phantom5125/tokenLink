import Foundation
import TokenLinkCore

public enum DevicePhase: Equatable, Sendable {
    case unbound, disconnected, scanning, connecting, connected, syncing, synced(Date), stale
}

public struct DeviceDescriptor: Equatable, Sendable {
    public let identifier: UUID
    public let advertisedName: String?
    public init(identifier: UUID, advertisedName: String? = nil) {
        self.identifier = identifier
        self.advertisedName = advertisedName
    }
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
        phase = .scanning
        guard try await transport.discoveredIdentifiers().contains(boundIdentifier) else {
            phase = .disconnected; return
        }
        phase = .connecting
        try await transport.connect(identifier: boundIdentifier)
        phase = .connected
    }

    public func sync(_ data: Data, now: Date = .now) async throws {
        phase = .syncing
        try await transport.writeWithResponse(data)
        phase = .synced(now)
    }
}