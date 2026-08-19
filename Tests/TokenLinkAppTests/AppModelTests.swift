import Foundation
import Testing
import TokenLinkCore
@testable import TokenLinkApp

private actor CountingRefresher: AppRefreshing {
    private(set) var count = 0
    func refresh() async { count += 1 }
}

private final class TestNow: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
    func callAsFunction() -> Date { value }
}

private func snapshot(_ provider: ProviderID, remaining: Double) -> QuotaSnapshot {
    QuotaSnapshot(
        provider: provider,
        planLabel: nil,
        windows: [.init(
            id: "primary",
            label: "Primary",
            usedPercent: 100 - remaining,
            remainingPercent: remaining,
            remainingCount: nil,
            limitCount: nil,
            resetsAt: nil)],
        source: provider == .codex ? .localAppServer : .apiKey,
        fetchedAt: Date(timeIntervalSince1970: 100))
}

@MainActor @Test func appModelHighlightsLowestHealthyWindow() async {
    let model = AppModel.preview(snapshots: [
        snapshot(.codex, remaining: 72),
        snapshot(.kimi, remaining: 24),
    ])
    #expect(model.highlight?.provider == .kimi)
    #expect(model.highlight?.window.remainingPercent == 24)
}

@MainActor @Test func manualRefreshIsThrottledForTenSeconds() async {
    let clock = TestNow(Date(timeIntervalSince1970: 100))
    let refresher = CountingRefresher()
    let model = AppModel(refresher: refresher, now: clock.callAsFunction)
    await model.refreshManually()
    await model.refreshManually()
    #expect(await refresher.count == 1)

    clock.value = Date(timeIntervalSince1970: 111)
    await model.refreshManually()
    #expect(await refresher.count == 2)
}

@MainActor @Test func schedulerUsesConfiguredFiveMinuteInterval() {
    let scheduler = RefreshScheduler(minutes: 5)
    #expect(scheduler.interval == .seconds(300))
}

@Test func diagnosticExporterRedactsEverySensitiveCategory() throws {
    let input: [String: Any] = [
        "api_key": "sk-live-value",
        "authorization": "Bearer live-token",
        "path": "/Users/alice/Library/Application Support/TokenLink/config.json",
        "username": "alice",
        "device": "32FA7010-3C2A-4C1D-AE44-123456789ABC",
        "account": "personal@example.com",
        "nested": ["secret": "should-not-survive"],
    ]
    let sanitized = DiagnosticExporter.sanitize(
        input,
        homeURL: URL(filePath: "/Users/alice", directoryHint: .isDirectory),
        accountLabels: ["personal@example.com"])
    let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
    let output = String(decoding: data, as: UTF8.self)

    for sensitive in [
        "sk-live-value",
        "live-token",
        "/Users/alice",
        "alice",
        "32FA7010-3C2A-4C1D-AE44-123456789ABC",
        "personal@example.com",
        "should-not-survive",
    ] {
        #expect(!output.contains(sensitive))
    }
}
