import Foundation
import TokenLinkCore

public enum GLMParseError: Error, Equatable {
  case service(code: Int)
  case emptyLimits
}

public enum GLMParser {
  public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    let response = try JSONDecoder().decode(GLMResponse.self, from: data)
    guard response.code == 200 else {
      throw GLMParseError.service(code: response.code)
    }
    let windows = response.data.limits.compactMap { limit -> QuotaWindow? in
      guard let descriptor = descriptor(for: limit), let usedPercent = limit.usedPercent else {
        return nil
      }
      let remainingPercent = limit.remainingPercent ?? (100 - usedPercent)
      return QuotaWindow(
        id: descriptor.id,
        label: descriptor.label,
        usedPercent: usedPercent,
        remainingPercent: remainingPercent,
        remainingCount: limit.remaining,
        limitCount: limit.usage,
        resetsAt: limit.resetTime.map {
          Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1_000 : $0)
        })
    }
    guard !windows.isEmpty else { throw GLMParseError.emptyLimits }
    return QuotaSnapshot(
      provider: .glm,
      planLabel: response.data.level,
      windows: windows,
      source: .apiKey,
      fetchedAt: fetchedAt)
  }

  private static func descriptor(for limit: GLMLimit) -> (id: String, label: String)? {
    guard limit.type == "TOKENS_LIMIT" || limit.type == "TIME_LIMIT" else { return nil }
    if let legacyUnit = limit.unit.textValue {
      switch legacyUnit.lowercased() {
      case "5h": return ("5h", "5 hours")
      case "weekly", "week": return ("weekly", "Weekly")
      case "monthly", "month": return ("monthly", "Monthly")
      default: return (legacyUnit, legacyUnit)
      }
    }

    let unit = limit.unit.numberValue
    let number = limit.number ?? 1
    switch (limit.type, unit, number) {
    case ("TOKENS_LIMIT", 3, 5): return ("5h", "5 hours")
    case ("TOKENS_LIMIT", 6, 1): return ("weekly", "Weekly")
    case ("TOKENS_LIMIT", 5, 1): return ("monthly", "Monthly")
    case ("TIME_LIMIT", 5, 1): return ("mcp-monthly", "MCP monthly")
    default:
      guard let unit else { return nil }
      let prefix = limit.type == "TOKENS_LIMIT" ? "tokens" : "mcp"
      return ("\(prefix)-\(unit)-\(number)", "\(prefix.uppercased()) quota")
    }
  }
}

private struct GLMResponse: Decodable {
  let code: Int
  let data: GLMData
}

private struct GLMData: Decodable {
  let limits: [GLMLimit]
  let level: String?
}

private struct GLMLimit: Decodable {
  let type: String
  let unit: FlexibleUnit
  let number: Int?
  let percentage: Double?
  let currentValue: Double?
  let usage: Double?
  let remaining: Double?
  let legacyUsedPercent: Double?
  let remainingPercent: Double?
  let resetTime: Double?

  var usedPercent: Double? { percentage ?? legacyUsedPercent }

  enum CodingKeys: String, CodingKey {
    case type
    case unit
    case number
    case percentage
    case currentValue
    case usage
    case remaining
    case nextResetTime
    case legacyUsedPercent = "used_percent"
    case remainingPercent = "remaining_percent"
    case legacyResetTime = "reset_time"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    unit = try container.decode(FlexibleUnit.self, forKey: .unit)
    number = try container.decodeIfPresent(Int.self, forKey: .number)
    percentage = try container.decodeIfPresent(Double.self, forKey: .percentage)
    currentValue = try container.decodeIfPresent(Double.self, forKey: .currentValue)
    usage = try container.decodeIfPresent(Double.self, forKey: .usage)
    remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
    legacyUsedPercent = try container.decodeIfPresent(Double.self, forKey: .legacyUsedPercent)
    remainingPercent = try container.decodeIfPresent(Double.self, forKey: .remainingPercent)
    resetTime =
      try container.decodeIfPresent(Double.self, forKey: .nextResetTime)
      ?? container.decodeIfPresent(Double.self, forKey: .legacyResetTime)
  }
}

private enum FlexibleUnit: Decodable {
  case number(Int)
  case text(String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self) {
      self = .number(number)
    } else {
      self = .text(try container.decode(String.self))
    }
  }

  var numberValue: Int? {
    guard case .number(let value) = self else { return nil }
    return value
  }

  var textValue: String? {
    guard case .text(let value) = self else { return nil }
    return value
  }
}
