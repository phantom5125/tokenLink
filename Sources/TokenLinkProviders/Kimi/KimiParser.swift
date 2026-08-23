import Foundation
import TokenLinkCore

public enum KimiParser {
  public static func parse(data: Data, fetchedAt: Date, source: CredentialSource) throws
    -> QuotaSnapshot
  {
    let response = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
    let weekly = try response.usage.quotaWindow(id: "weekly", label: "Weekly")
    let rolling = try response.limits.compactMap { limit -> QuotaWindow? in
      guard limit.window.duration == 300 else { return nil }
      if let detail = limit.detail {
        return try detail.quotaWindow(id: "5h", label: "5 hours")
      }
      return QuotaWindow(
        id: "5h", label: "5 hours", usedPercent: 0,
        remainingPercent: 100, remainingCount: nil, limitCount: nil, resetsAt: nil)
    }
    return QuotaSnapshot(
      provider: .kimi, planLabel: response.subType,
      windows: [weekly] + rolling, source: source, fetchedAt: fetchedAt)
  }
}

private struct KimiUsageResponse: Decodable {
  let subType: String
  let usage: KimiUsage
  let limits: [KimiLimit]
}

private struct KimiUsage: Decodable {
  let limit: FlexibleStringNumber
  let used: FlexibleStringNumber
  let remaining: FlexibleStringNumber
  let resetTime: String?
}

private struct KimiLimit: Decodable {
  let window: KimiWindow
  let detail: KimiUsage?
}

private struct KimiWindow: Decodable {
  let duration: Int
  let timeUnit: String
}

private struct FlexibleStringNumber: Decodable {
  let value: Double

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let double = try? container.decode(Double.self) {
      value = double
    } else if let int = try? container.decode(Int.self) {
      value = Double(int)
    } else if let string = try? container.decode(String.self), let parsed = Double(string) {
      value = parsed
    } else {
      value = 0
    }
  }
}

extension KimiUsage {
  fileprivate func quotaWindow(id: String, label: String) throws -> QuotaWindow {
    let total = limit.value
    let used = used.value
    let remaining = remaining.value
    let resetAt = resetTime.flatMap { KimiParser.parseISO8601($0) }
    if total > 0 {
      let usedPercent = (used / total) * 100
      let remainingPercent = (remaining / total) * 100
      return QuotaWindow(
        id: id, label: label, usedPercent: usedPercent,
        remainingPercent: remainingPercent,
        remainingCount: remaining, limitCount: total, resetsAt: resetAt)
    }
    return QuotaWindow(
      id: id, label: label, usedPercent: 0,
      remainingPercent: 100, remainingCount: remaining,
      limitCount: total, resetsAt: resetAt)
  }
}

extension KimiParser {
  static func parseISO8601(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
  }
}
