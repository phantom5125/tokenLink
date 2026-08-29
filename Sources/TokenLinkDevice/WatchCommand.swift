import Foundation
import TokenLinkCore

/// Commands sent from the watch to the Mac over the GATT characteristic
/// `7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C04` (watch notifies, Mac receives).
public enum WatchCommand: Equatable, Sendable {
  case focus(slot: Int)
  case refresh

  private struct Envelope: Decodable {
    let action: String
    let slot: Int?
  }

  /// Decodes a command frame. Malformed JSON, unknown actions, and
  /// out-of-range slots all return nil; the caller counts and drops them
  /// instead of propagating an error.
  public static func decode(_ data: Data) -> WatchCommand? {
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
    else { return nil }
    switch envelope.action {
    case "focus":
      guard let slot = envelope.slot, WorkItemPayload.slotRange.contains(slot)
      else { return nil }
      return .focus(slot: slot)
    case "refresh":
      return .refresh
    default:
      return nil
    }
  }
}
