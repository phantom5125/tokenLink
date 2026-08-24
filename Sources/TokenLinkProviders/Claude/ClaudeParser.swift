import Foundation
import TokenLinkCore

public enum ClaudeParseError: Error, Equatable {
  case noUsableWindows
}

/// Parses the Claude Code OAuth usage endpoint
/// (`GET https://api.anthropic.com/api/oauth/usage`). `utilization` is the
/// *used* percentage of a window, so remaining is `100 - utilization`.
public enum ClaudeParser {
  public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
    let windows = response.windows
    guard !windows.isEmpty else { throw ClaudeParseError.noUsableWindows }
    return QuotaSnapshot(
      provider: .claude,
      planLabel: nil,
      windows: windows,
      source: .cliCredential,
      fetchedAt: fetchedAt)
  }

  /// Human-readable label for an extra `seven_day_*` field, e.g.
  /// `seven_day_opus` -> "Seven day opus".
  static func humanizedLabel(for field: String) -> String {
    let words = field.replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }
}

private struct ClaudeUsageResponse: Decodable {
  let windows: [QuotaWindow]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    var known: [String: QuotaWindow] = [:]
    var extras: [(key: String, window: QuotaWindow)] = []
    for key in container.allKeys {
      guard let payload = try? container.decode(ClaudeWindowPayload.self, forKey: key),
        let utilization = payload.utilization
      else { continue }
      let resetsAt = payload.resetsAt.flatMap(Self.parseISO8601Date)
      let window: QuotaWindow
      switch key.stringValue {
      case "five_hour":
        window = Self.window(
          id: "5h", label: "5 hours", utilization: utilization, resetsAt: resetsAt)
      case "seven_day":
        window = Self.window(
          id: "weekly", label: "Weekly", utilization: utilization, resetsAt: resetsAt)
      default:
        window = Self.window(
          id: key.stringValue,
          label: ClaudeParser.humanizedLabel(for: key.stringValue),
          utilization: utilization,
          resetsAt: resetsAt)
        extras.append((key.stringValue, window))
        continue
      }
      known[key.stringValue] = window
    }
    var ordered: [QuotaWindow] = []
    if let fiveHour = known["five_hour"] { ordered.append(fiveHour) }
    if let sevenDay = known["seven_day"] { ordered.append(sevenDay) }
    ordered.append(contentsOf: extras.sorted { $0.key < $1.key }.map(\.window))
    self.windows = ordered
  }

  private static func window(
    id: String,
    label: String,
    utilization: Double,
    resetsAt: Date?
  ) -> QuotaWindow {
    QuotaWindow(
      id: id,
      label: label,
      usedPercent: utilization,
      remainingPercent: 100 - utilization,
      remainingCount: nil,
      limitCount: nil,
      resetsAt: resetsAt)
  }

  private static func parseISO8601Date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
  }
}

private struct ClaudeWindowPayload: Decodable {
  let utilization: Double?
  let resetsAt: String?

  enum CodingKeys: String, CodingKey {
    case utilization
    case resetsAt = "resets_at"
  }
}

private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}
