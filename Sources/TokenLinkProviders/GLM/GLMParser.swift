import Foundation
import TokenLinkCore

public enum GLMParseError: Error, Equatable {
    case errorStatus(Int)
}

public enum GLMParser {
    public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(GLMQuotaResponse.self, from: data)
        guard response.code == 200 else { throw GLMParseError.errorStatus(response.code) }
        let windows = response.data.limits.map(Self.makeWindow)
        return QuotaSnapshot(
            provider: .glm, planLabel: nil,
            windows: windows, source: .apiKey, fetchedAt: fetchedAt)
    }

    private static func makeWindow(from limit: GLMLimit) -> QuotaWindow {
        let label = label(for: limit.unit)
        let resetAt = limit.resetTime.map { Self.date(fromMillis: $0) }
        return QuotaWindow(
            id: limit.unit, label: label,
            usedPercent: limit.usedPercent, remainingPercent: limit.remainingPercent,
            remainingCount: nil, limitCount: nil, resetsAt: resetAt)
    }

    private static func label(for unit: String) -> String {
        switch unit {
        case "5h": return "5 hours"
        case "weekly": return "Weekly"
        default: return unit
        }
    }

    private static func date(fromMillis millis: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
    }
}

private struct GLMQuotaResponse: Decodable {
    let code: Int
    let data: GLMData
}

private struct GLMData: Decodable {
    let limits: [GLMLimit]
}

private struct GLMLimit: Decodable {
    let type: String
    let unit: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetTime: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case unit
        case usedPercent = "used_percent"
        case remainingPercent = "remaining_percent"
        case resetTime = "reset_time"
    }
}