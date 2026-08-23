import Foundation
import Testing
@testable import TokenLinkApp
@testable import TokenLinkCore

private actor CountingRefresher: AppRefreshing {
    private(set) var count = 0
    func refresh() async { count += 1 }
}

private final class TestNow: @unchecked Sendable {
    let value: Date
    init(_ value: Date) { self.value = value }
    func callAsFunction() -> Date { value }
}

private func snapshot(_ provider: ProviderID, remaining: Double) -> QuotaSnapshot {
    QuotaSnapshot(provider: provider, planLabel: nil,
        windows: [.init(id: "primary", label: "Primary", usedPercent: 100 - remaining,
                        remainingPercent: remaining, remainingCount: nil,
                        limitCount: nil, resetsAt: nil)],
        source: provider == .codex ? .localAppServer : .apiKey,
        fetchedAt: Date(timeIntervalSince1970: 100))
}

@MainActor @Test func appModelHighlightsLowestHealthyWindow() async {
    let model = AppModel.preview(snapshots: [snapshot(.codex, remaining: 72),
                                             snapshot(.kimi, remaining: 24)])
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
}

@Test func schedulerUsesConfiguredFiveMinuteInterval() {
    let scheduler = RefreshScheduler(minutes: 5)
    #expect(scheduler.interval == .seconds(300))
}

@Test func schedulerFallsBackToFiveMinutesForUnsupportedValues() {
    #expect(RefreshScheduler(minutes: 7).minutes == 5)
    #expect(RefreshScheduler(minutes: 1).minutes == 1)
}

@Test func diagnosticsRedactEverySensitiveCategory() throws {
    let exporter = DiagnosticExporter()
    let home = NSHomeDirectory()
    let uuid = "12345678-1234-1234-1234-1234567890AB"
    let payload: [String: Any] = [
        "apiKey": "sk-live-secret",
        "paths": ["\(home)/Library/token", "/tmp/ok"],
        "device": uuid,
        "nested": ["authorization": "Bearer abc", "note": "user \(NSUserName()) ran it"],
    ]
    let redacted = exporter.redact(payload)
    let data = try JSONSerialization.data(withJSONObject: redacted)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("sk-live-secret"))
    #expect(!text.contains("Bearer abc"))
    #expect(!text.contains(uuid))
    #expect(!text.contains(NSUserName()))
    #expect(!text.contains(home))
}
