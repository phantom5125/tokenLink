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
        let windows = response.data.limits.map { limit in
            QuotaWindow(
                id: limit.unit,
                label: label(for: limit.unit),
                usedPercent: limit.usedPercent,
                remainingPercent: limit.remainingPercent,
                remainingCount: nil,
                limitCount: nil,
                resetsAt: limit.resetTime.map {
                    Date(timeIntervalSince1970: $0 / 1_000)
                })
        }
        guard !windows.isEmpty else { throw GLMParseError.emptyLimits }
        return QuotaSnapshot(
            provider: .glm,
            planLabel: nil,
            windows: windows,
            source: .apiKey,
            fetchedAt: fetchedAt)
    }

    private static func label(for unit: String) -> String {
        switch unit.lowercased() {
        case "5h": "5 hours"
        case "weekly", "week": "Weekly"
        default: unit
        }
    }
}

private struct GLMResponse: Decodable {
    let code: Int
    let data: GLMData
}

private struct GLMData: Decodable {
    let limits: [GLMLimit]
}

private struct GLMLimit: Decodable {
    let type: String
    let unit: String
    let usedPercent: Double?
    let remainingPercent: Double
    let resetTime: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case unit
        case usedPercent = "used_percent"
        case remainingPercent = "remaining_percent"
        case resetTime = "reset_time"
    }
}
