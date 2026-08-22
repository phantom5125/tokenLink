import Foundation
import TokenLinkCore

public enum MiniMaxParseError: Error, Equatable {
    case errorEnvelope(statusCode: Int, message: String)
    case missingModelRemains
}

public enum MiniMaxParser {
    public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: data)
        let envelope = response.baseResp
        guard envelope.statusCode == 0 else {
            throw MiniMaxParseError.errorEnvelope(
                statusCode: envelope.statusCode, message: envelope.statusMsg)
        }
        guard let rows = response.modelRemains, let row = rows.first else {
            throw MiniMaxParseError.missingModelRemains
        }
        let fiveHourReset = row.currentIntervalResetTime.map { Self.date(fromMillis: $0) }
        let weeklyReset = row.currentWeeklyResetTime.map { Self.date(fromMillis: $0) }
        let fiveHour = QuotaWindow(
            id: "5h", label: "5 hours",
            usedPercent: 100 - row.currentIntervalRemainingPercent,
            remainingPercent: row.currentIntervalRemainingPercent,
            remainingCount: nil, limitCount: nil, resetsAt: fiveHourReset)
        let weekly = QuotaWindow(
            id: "weekly", label: "Weekly",
            usedPercent: 100 - row.currentWeeklyRemainingPercent,
            remainingPercent: row.currentWeeklyRemainingPercent,
            remainingCount: nil, limitCount: nil, resetsAt: weeklyReset)
        return QuotaSnapshot(
            provider: .minimax, planLabel: row.modelName,
            windows: [fiveHour, weekly],
            source: .apiKey, fetchedAt: fetchedAt)
    }

    private static func date(fromMillis millis: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
    }
}

private struct MiniMaxRemainsResponse: Decodable {
    let modelRemains: [MiniMaxModelRemain]?
    let baseResp: MiniMaxBaseResp

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

private struct MiniMaxModelRemain: Decodable {
    let modelName: String
    let currentIntervalRemainingPercent: Double
    let currentWeeklyRemainingPercent: Double
    let currentIntervalResetTime: Int?
    let currentWeeklyResetTime: Int?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
        case currentIntervalResetTime = "current_interval_reset_time"
        case currentWeeklyResetTime = "current_weekly_reset_time"
    }
}

private struct MiniMaxBaseResp: Decodable {
    let statusCode: Int
    let statusMsg: String

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}