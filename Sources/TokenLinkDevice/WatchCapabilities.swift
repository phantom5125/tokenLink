import Foundation

/// Capabilities reported by the firmware through the read-only GATT
/// characteristic `7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C03`.
public struct WatchCapabilities: Codable, Equatable, Sendable {
  public let protocolVersions: [Int]  // e.g. [1, 2]
  public let firmware: String?  // display only

  public init(protocolVersions: [Int], firmware: String? = nil) {
    self.protocolVersions = protocolVersions
    self.firmware = firmware
  }

  enum CodingKeys: String, CodingKey {
    case protocolVersions = "protocol_versions"
    case firmware
  }
}

/// Result of the per-connection protocol negotiation. Any failure to read or
/// parse capabilities silently falls back to `.v1`.
public enum NegotiatedProtocol: Equatable, Sendable {
  case v1
  case v2(WatchCapabilities)
}
