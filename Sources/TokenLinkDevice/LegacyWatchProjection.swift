import Foundation
import TokenLinkCore

public enum WatchProjectionError: Error, Equatable {
    case notCodex
    case missingPrimary
    case payloadTooLarge
}

private struct LegacyQuotaPayload: Encodable {
    let remainingPercent: Double
    let resetInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case resetInSeconds = "reset_in_seconds"
    }
}

public enum LegacyWatchProjection {
    public static func encode(snapshot: QuotaSnapshot, now: Date) throws -> Data {
        guard snapshot.provider == .codex else {
            throw WatchProjectionError.notCodex
        }
        guard let window = snapshot.windows.first(where: { $0.id == "primary" }) else {
            throw WatchProjectionError.missingPrimary
        }
        let seconds = max(0, Int((window.resetsAt ?? now).timeIntervalSince(now)))
        let data = try JSONEncoder().encode(LegacyQuotaPayload(
            remainingPercent: window.remainingPercent,
            resetInSeconds: seconds))
        guard data.count <= 512 else {
            throw WatchProjectionError.payloadTooLarge
        }
        return data
    }
}
