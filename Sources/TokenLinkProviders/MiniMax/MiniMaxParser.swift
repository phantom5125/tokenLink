import Foundation
import TokenLinkCore

public enum MiniMaxParseError: Error, Equatable {
    case service(statusCode: Int, message: String)
    case missingModelRemains
}

public enum MiniMaxParser {
    public static func parse(data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(MiniMaxResponse.self, from: data)
        guard response.baseResponse.statusCode == 0 else {
            throw MiniMaxParseError.service(
                statusCode: response.baseResponse.statusCode,
                message: response.baseResponse.statusMessage)
        }
        guard let model = response.modelRemains?.first else {
            throw MiniMaxParseError.missingModelRemains
        }

        let intervalRemaining = model.currentIntervalRemainingPercent
        let weeklyRemaining = model.currentWeeklyRemainingPercent
        return QuotaSnapshot(
            provider: .minimax,
            planLabel: model.modelName,
            windows: [
                QuotaWindow(
                    id: "5h",
                    label: "5 hours",
                    usedPercent: 100 - intervalRemaining,
                    remainingPercent: intervalRemaining,
                    remainingCount: nil,
                    limitCount: nil,
                    resetsAt: model.currentIntervalResetTime.map(Date.fromMilliseconds)),
                QuotaWindow(
                    id: "weekly",
                    label: "Weekly",
                    usedPercent: 100 - weeklyRemaining,
                    remainingPercent: weeklyRemaining,
                    remainingCount: nil,
                    limitCount: nil,
                    resetsAt: model.currentWeeklyResetTime.map(Date.fromMilliseconds)),
            ],
            source: .apiKey,
            fetchedAt: fetchedAt)
    }
}

private struct MiniMaxResponse: Decodable {
    let modelRemains: [MiniMaxModelRemain]?
    let baseResponse: MiniMaxBaseResponse

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResponse = "base_resp"
    }
}

private struct MiniMaxBaseResponse: Decodable {
    let statusCode: Int
    let statusMessage: String

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMessage = "status_msg"
    }
}

private struct MiniMaxModelRemain: Decodable {
    let modelName: String
    let currentIntervalRemainingPercent: Double
    let currentWeeklyRemainingPercent: Double
    let currentIntervalResetTime: Double?
    let currentWeeklyResetTime: Double?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
        case currentIntervalResetTime = "current_interval_reset_time"
        case currentWeeklyResetTime = "current_weekly_reset_time"
    }
}

private extension Date {
    static func fromMilliseconds(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}
