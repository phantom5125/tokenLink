import Foundation

/// Stable identifier for a built-in or packaged watch face.
///
/// IDs use a deliberately small, path-safe alphabet so they can later name
/// package directories without becoming filesystem paths themselves.
public struct WatchFaceID: RawRepresentable, Codable, Hashable, Sendable {
  public static let maximumLength = 64

  public static let data = WatchFaceID(rawValue: "data")!
  public static let pet = WatchFaceID(rawValue: "pet")!

  public let rawValue: String

  public init?(rawValue: String) {
    guard Self.isValid(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let value = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid watch face identifier")
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static func isValid(_ rawValue: String) -> Bool {
    guard !rawValue.isEmpty, rawValue.utf8.count <= maximumLength else { return false }
    return rawValue.utf8.allSatisfy { byte in
      switch byte {
      case 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F:
        true
      default:
        false
      }
    }
  }
}
