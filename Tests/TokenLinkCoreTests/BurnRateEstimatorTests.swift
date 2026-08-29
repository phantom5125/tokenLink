import Foundation
import Testing

@testable import TokenLinkCore

private final class BurnTestClock: @unchecked Sendable {
  var value: Date
  init(_ value: Date) { self.value = value }
}

@Test func estimatorProjectsLinearBurn() {
  let t0 = Date(timeIntervalSince1970: 1_000_000)
  let estimate = BurnRateEstimator.estimate(
    windowID: "5h",
    samples: [
      .init(date: t0, remaining: 80),
      .init(date: t0.addingTimeInterval(3_600), remaining: 60),
    ],
    now: t0.addingTimeInterval(3_600))

  let estimate2 = estimate
  #expect(estimate2?.percentPerHour == 20)
  #expect(estimate2?.depletesAt == t0.addingTimeInterval(3_600 + 3 * 3_600))
}

@Test func estimatorStaysSilentWithTooLittleData() {
  let t0 = Date(timeIntervalSince1970: 1_000_000)
  #expect(
    BurnRateEstimator.estimate(
      windowID: "5h",
      samples: [.init(date: t0, remaining: 80)],
      now: t0) == nil)
  // Span below the 30-minute minimum is noise.
  #expect(
    BurnRateEstimator.estimate(
      windowID: "5h",
      samples: [
        .init(date: t0, remaining: 80),
        .init(date: t0.addingTimeInterval(600), remaining: 70),
      ],
      now: t0.addingTimeInterval(600)) == nil)
}

@Test func estimatorStaysSilentWhenNotBurning() {
  let t0 = Date(timeIntervalSince1970: 1_000_000)
  #expect(
    BurnRateEstimator.estimate(
      windowID: "weekly",
      samples: [
        .init(date: t0, remaining: 60),
        .init(date: t0.addingTimeInterval(3_600), remaining: 75),
      ],
      now: t0.addingTimeInterval(3_600)) == nil)
}

@Test func estimatorIgnoresSamplesOlderThanSixHours() {
  let t0 = Date(timeIntervalSince1970: 1_000_000)
  let now = t0.addingTimeInterval(7 * 3_600)
  // Only the stale sample falls outside the window; nothing usable remains.
  #expect(
    BurnRateEstimator.estimate(
      windowID: "5h",
      samples: [
        .init(date: t0, remaining: 90),
        .init(date: now, remaining: 50),
      ],
      now: now) == nil)
}

@Test func storeProjectsBurnForMostConstrainedWindow() async {
  let t0 = Date(timeIntervalSince1970: 1_000_000)
  let clock = BurnTestClock(t0)
  let store = ProviderStore(now: { clock.value })
  let account = UUID()

  func snapshot(_ remaining: Double, at date: Date) -> QuotaSnapshot {
    QuotaSnapshot(
      provider: .kimi, planLabel: nil,
      windows: [
        .init(
          id: "5h", label: "5 hours", usedPercent: 100 - remaining,
          remainingPercent: remaining, remainingCount: nil, limitCount: nil,
          resetsAt: nil)
      ],
      source: .apiKey, fetchedAt: date)
  }

  await store.accept(.success(snapshot(80, at: t0)), accountID: account)
  #expect(await store.burnEstimate(for: account) == nil)

  clock.value = t0.addingTimeInterval(3_600)
  await store.accept(.success(snapshot(60, at: clock.value)), accountID: account)

  let estimate = await store.burnEstimate(for: account)
  #expect(estimate?.windowID == "5h")
  #expect(estimate?.percentPerHour == 20)
  #expect(await store.allBurnEstimates()[account]?.windowID == "5h")
}
