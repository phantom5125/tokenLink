import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkApp

private func state(
  remaining: Double,
  phase: ProviderPhase = .healthy,
  resetsAt: Date? = nil,
  error: ProviderFailure? = nil
) -> ProviderState {
  ProviderState(
    phase: phase,
    snapshot: QuotaSnapshot(
      provider: .kimi, planLabel: nil,
      windows: [
        .init(
          id: "5h", label: "5 hours", usedPercent: 100 - remaining,
          remainingPercent: remaining, remainingCount: nil, limitCount: nil,
          resetsAt: resetsAt)
      ],
      source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 100)),
    error: error)
}

private let testStrings = NotificationPolicy.Strings(
  lowQuotaTitle: "low", lowQuotaBody: "%@ at %d%%",
  authFailureTitle: "auth", authFailureBody: "%@ rejected",
  resetTitle: "reset", resetBody: "%@ %@ reset")

private func names(_ id: UUID) -> String { "Kimi" }

@Test func lowQuotaNotifiesOncePerWindowUntilRecovery() {
  var policy = NotificationPolicy()
  let account = UUID()
  let now = Date(timeIntervalSince1970: 1_000)

  let first = policy.evaluate(
    current: [account: state(remaining: 20)],
    nameForAccount: names, strings: testStrings, now: now)
  #expect(first.count == 1)
  #expect(first[0].title == "low")
  #expect(first[0].body == "Kimi at 20%")

  // Still low: no repeat.
  #expect(
    policy.evaluate(
      current: [account: state(remaining: 18)],
      nameForAccount: names, strings: testStrings,
      now: now.addingTimeInterval(60)
    ).isEmpty)

  // Recovery above the threshold re-arms the latch.
  #expect(
    policy.evaluate(
      current: [account: state(remaining: 80)],
      nameForAccount: names, strings: testStrings,
      now: now.addingTimeInterval(120)
    ).isEmpty)
  let again = policy.evaluate(
    current: [account: state(remaining: 10)],
    nameForAccount: names, strings: testStrings, now: now.addingTimeInterval(180))
  #expect(again.count == 1)
}

@Test func authFailureNotifiesOnceAndRearmsOnHealthy() {
  var policy = NotificationPolicy()
  let account = UUID()
  let now = Date(timeIntervalSince1970: 1_000)
  let failed = state(
    remaining: 50, phase: .error, error: .init(kind: .authentication, message: "401"))

  #expect(
    policy.evaluate(
      current: [account: failed], nameForAccount: names, strings: testStrings,
      now: now
    ).count == 1)
  #expect(
    policy.evaluate(
      current: [account: failed], nameForAccount: names, strings: testStrings,
      now: now.addingTimeInterval(60)
    ).isEmpty)
  #expect(
    policy.evaluate(
      current: [account: state(remaining: 50)], nameForAccount: names,
      strings: testStrings, now: now.addingTimeInterval(120)
    ).isEmpty)
  #expect(
    policy.evaluate(
      current: [account: failed], nameForAccount: names, strings: testStrings,
      now: now.addingTimeInterval(180)
    ).count == 1)
}

@Test func resetMomentNotifiesExactlyWhenItPasses() {
  var policy = NotificationPolicy()
  let account = UUID()
  let t0 = Date(timeIntervalSince1970: 1_000)
  let resetAt = t0.addingTimeInterval(300)

  // First evaluation before the reset: establishes lastEvaluatedAt.
  #expect(
    policy.evaluate(
      current: [account: state(remaining: 90, resetsAt: resetAt)],
      nameForAccount: names, strings: testStrings, now: t0
    ).isEmpty)

  // Evaluation after the reset moment: fires once.
  let fired = policy.evaluate(
    current: [account: state(remaining: 100, resetsAt: resetAt)],
    nameForAccount: names, strings: testStrings, now: t0.addingTimeInterval(600))
  #expect(fired.count == 1)
  #expect(fired[0].title == "reset")

  // The same reset moment never fires twice.
  #expect(
    policy.evaluate(
      current: [account: state(remaining: 99, resetsAt: resetAt)],
      nameForAccount: names, strings: testStrings,
      now: t0.addingTimeInterval(900)
    ).isEmpty)
}

@Test func policyIgnoresNonAuthErrors() {
  var policy = NotificationPolicy()
  let account = UUID()
  let networkError = state(
    remaining: 50, phase: .error, error: .network("offline"))
  #expect(
    policy.evaluate(
      current: [account: networkError], nameForAccount: names,
      strings: testStrings, now: Date(timeIntervalSince1970: 1_000)
    ).isEmpty)
}
