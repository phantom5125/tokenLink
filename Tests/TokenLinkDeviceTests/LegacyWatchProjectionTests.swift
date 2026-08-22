import Foundation
import Testing
@testable import TokenLinkCore
@testable import TokenLinkDevice

@Test func legacyProjectionEncodesExactV1Keys() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = QuotaSnapshot(
        provider: .codex, planLabel: nil,
        windows: [.init(id: "primary", label: "Primary", usedPercent: 28,
                        remainingPercent: 72, remainingCount: nil, limitCount: nil,
                        resetsAt: Date(timeIntervalSince1970: 1_900))],
        source: .localAppServer, fetchedAt: now)
    let data = try LegacyWatchProjection.encode(snapshot: snapshot, now: now)
    let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(object.keys.sorted() == ["remaining_percent", "reset_in_seconds"])
    #expect(object["remaining_percent"] as? Double == 72)
    #expect(object["reset_in_seconds"] as? Int == 900)
}

@Test func legacyProjectionRejectsNonCodexSnapshots() {
    #expect(throws: WatchProjectionError.self) {
        try LegacyWatchProjection.encode(snapshot: .init(provider: .kimi, planLabel: nil,
            windows: [], source: .apiKey, fetchedAt: .distantPast), now: .now)
    }
}