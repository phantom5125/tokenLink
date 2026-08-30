import Foundation
import Testing
@testable import TokenLinkCore

@Test func fairPaceWeeklyWindowOneDayIn() {
  // Weekly window resetting in exactly 6 days: even pace expects 6/7 left.
  let now = Date(timeIntervalSince1970: 1_000_000)
  let resetsAt = now.addingTimeInterval(6 * 86_400)
  let expected = FairPace.expectedRemaining(windowID: "weekly", resetsAt: resetsAt, now: now)
  #expect(expected != nil)
  #expect(abs(expected! - 600.0 / 7.0) < 0.01)
}

@Test func fairPaceFiveHourWindowHalfway() {
  let now = Date(timeIntervalSince1970: 1_000_000)
  let resetsAt = now.addingTimeInterval(2.5 * 3_600)
  let expected = FairPace.expectedRemaining(windowID: "5h", resetsAt: resetsAt, now: now)
  #expect(expected == 50)
}

@Test func fairPaceExposesKnownWatchDurationsAndAliases() {
  #expect(FairPace.duration(for: "5H")! == 18_000.0)
  #expect(FairPace.duration(for: "week")! == 604_800.0)
  #expect(FairPace.duration(for: "seven_day_opus")! == 604_800.0)
  #expect(FairPace.duration(for: "mcp-monthly")! == 2_592_000.0)
  #expect(FairPace.duration(for: "custom") == nil)
}

@Test func fairPaceUnknownOrInvalidInputsStaySilent() {
  let now = Date(timeIntervalSince1970: 1_000_000)
  // Unknown window id.
  #expect(
    FairPace.expectedRemaining(
      windowID: "custom", resetsAt: now.addingTimeInterval(86_400), now: now) == nil)
  // Missing reset time.
  #expect(FairPace.expectedRemaining(windowID: "weekly", resetsAt: nil, now: now) == nil)
  // Reset already passed.
  #expect(
    FairPace.expectedRemaining(
      windowID: "weekly", resetsAt: now.addingTimeInterval(-60), now: now) == nil)
  // Reset further out than the known duration (cycle start unknown).
  #expect(
    FairPace.expectedRemaining(
      windowID: "weekly", resetsAt: now.addingTimeInterval(8 * 86_400), now: now) == nil)
}
