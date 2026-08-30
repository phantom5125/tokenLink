import Foundation

public enum WatchCapabilityFeature: String, Sendable {
  case faceRuntime = "face_runtime"
  case facePackages = "face_packages"
  case faceBulkTransfer = "face_bulk_transfer"
}

/// Capabilities reported by the firmware through the read-only GATT
/// characteristic `7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C03`.
public struct WatchCapabilities: Codable, Equatable, Sendable {
  public let protocolVersions: [Int]  // e.g. [1, 2]
  public let firmware: String?  // display only
  public let features: [String]
  public let faceRuntimeVersions: [Int]
  public let faceAssetFormats: [String]
  public let maximumFacePackageBytes: Int?

  public init(
    protocolVersions: [Int],
    firmware: String? = nil,
    features: [String] = [],
    faceRuntimeVersions: [Int] = [],
    faceAssetFormats: [String] = [],
    maximumFacePackageBytes: Int? = nil
  ) {
    self.protocolVersions = protocolVersions
    self.firmware = firmware
    self.features = features
    self.faceRuntimeVersions = faceRuntimeVersions
    self.faceAssetFormats = faceAssetFormats
    self.maximumFacePackageBytes = maximumFacePackageBytes
  }

  public func supports(_ feature: WatchCapabilityFeature) -> Bool {
    features.contains(feature.rawValue)
  }

  public func supportsFaceRuntime(version: Int) -> Bool {
    supports(.faceRuntime) && faceRuntimeVersions.contains(version)
  }

  enum CodingKeys: String, CodingKey {
    case protocolVersions = "protocol_versions"
    case firmware
    case features
    case faceRuntimeVersions = "face_runtime_versions"
    case faceAssetFormats = "face_asset_formats"
    case maximumFacePackageBytes = "max_face_package_bytes"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      protocolVersions: try container.decode([Int].self, forKey: .protocolVersions),
      firmware: try container.decodeIfPresent(String.self, forKey: .firmware),
      features: try container.decodeIfPresent([String].self, forKey: .features) ?? [],
      faceRuntimeVersions: try container.decodeIfPresent(
        [Int].self, forKey: .faceRuntimeVersions) ?? [],
      faceAssetFormats: try container.decodeIfPresent(
        [String].self, forKey: .faceAssetFormats) ?? [],
      maximumFacePackageBytes: try container.decodeIfPresent(
        Int.self, forKey: .maximumFacePackageBytes))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(protocolVersions, forKey: .protocolVersions)
    try container.encodeIfPresent(firmware, forKey: .firmware)
    if !features.isEmpty {
      try container.encode(features, forKey: .features)
    }
    if !faceRuntimeVersions.isEmpty {
      try container.encode(faceRuntimeVersions, forKey: .faceRuntimeVersions)
    }
    if !faceAssetFormats.isEmpty {
      try container.encode(faceAssetFormats, forKey: .faceAssetFormats)
    }
    try container.encodeIfPresent(maximumFacePackageBytes, forKey: .maximumFacePackageBytes)
  }
}

/// Result of the per-connection protocol negotiation. Any failure to read or
/// parse capabilities silently falls back to `.v1`.
public enum NegotiatedProtocol: Equatable, Sendable {
  case v1
  case v2(WatchCapabilities)
}
