import Foundation
import TokenLinkCore

public enum KimiParseError: Error, Equatable {
  case invalidQuota
}

public enum KimiParser {
  public static func parse(
    data: Data,
    fetchedAt: Date,
    source: CredentialSource
  ) throws -> QuotaSnapshot {
    let response = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
    let weekly = try response.usage.quotaWindow(id: "weekly", label: "Weekly")
    let rolling = try response.limits.compactMap { limit -> QuotaWindow? in
      guard limit.window.duration == 300 else { return nil }
      return try limit.detail?.quotaWindow(id: "5h", label: "5 hours")
        ?? QuotaWindow(
          id: "5h",
          label: "5 hours",
          usedPercent: 0,
          remainingPercent: 100,
          remainingCount: nil,
          limitCount: nil,
          resetsAt: nil)
    }
    return QuotaSnapshot(
      provider: .kimi,
      planLabel: response.subType,
      windows: [weekly] + rolling,
      source: source,
      fetchedAt: fetchedAt)
  }
}

private struct KimiUsageResponse: Decodable {
  let subType: String?
  let usage: KimiQuotaDetail
  let limits: [KimiLimit]
}

private struct KimiLimit: Decodable {
  let window: KimiWindow
  let detail: KimiQuotaDetail?
}

private struct KimiWindow: Decodable {
  let duration: Int
  let timeUnit: String?
}

private struct KimiQuotaDetail: Decodable {
  let limit: FlexibleDouble
  let used: FlexibleDouble
  let remaining: FlexibleDouble
  let resetTime: String?

  func quotaWindow(id: String, label: String) throws -> QuotaWindow {
    guard limit.value > 0 else { throw KimiParseError.invalidQuota }
    let usedPercent = used.value / limit.value * 100
    let remainingPercent = remaining.value / limit.value * 100
    return QuotaWindow(
      id: id,
      label: label,
      usedPercent: usedPercent,
      remainingPercent: remainingPercent,
      remainingCount: remaining.value,
      limitCount: limit.value,
      resetsAt: resetTime.flatMap(parseISO8601Date))
  }

  private func parseISO8601Date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
  }
}

private struct FlexibleDouble: Decodable {
  let value: Double

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Double.self) {
      self.value = value
    } else if let text = try? container.decode(String.self), let value = Double(text) {
      self.value = value
    } else {
      throw KimiParseError.invalidQuota
    }
  }
}
