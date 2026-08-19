import Foundation
import Testing

@testable import TokenLinkCore

@Test func quotaWindowClampsPercentages() {
  let window = QuotaWindow(
    id: "weekly", label: "Weekly", usedPercent: 130,
    remainingPercent: -30, remainingCount: nil, limitCount: nil,
    resetsAt: nil)
  #expect(window.usedPercent == 100)
  #expect(window.remainingPercent == 0)
}

@Test func snapshotHighlightsLowestRemainingWindow() throws {
  let snapshot = QuotaSnapshot(
    provider: .kimi, planLabel: "Pro",
    windows: [
      .init(
        id: "weekly", label: "Weekly", usedPercent: 20,
        remainingPercent: 80, remainingCount: nil, limitCount: nil, resetsAt: nil),
      .init(
        id: "5h", label: "5 hours", usedPercent: 75,
        remainingPercent: 25, remainingCount: nil, limitCount: nil, resetsAt: nil),
    ],
    source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
  #expect(try #require(snapshot.mostConstrainedWindow).id == "5h")
}
