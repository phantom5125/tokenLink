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