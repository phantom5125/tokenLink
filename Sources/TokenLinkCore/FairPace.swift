import Foundation

/// Fair-pace reference: where a window *would* be if quota were consumed
/// evenly across the window. A 7-day window one day in sits at 6/7 remaining;
/// the UI draws a marker there so users can see at a glance whether they are
/// ahead of or behind an even pace.
public enum FairPace {
  /// Known window durations. Unknown ids get no marker rather than a guess.
  static let windowDurations: [String: TimeInterval] = [
    "5h": 5 * 3_600,
    "primary": 5 * 3_600,
    "weekly": 7 * 86_400,
    "monthly": 30 * 86_400,
  ]

  /// Expected remaining percent if the window were consumed evenly.
  /// Returns nil for unknown window kinds, missing reset times, or reset
  /// times inconsistent with the known duration.
  public static func expectedRemaining(
    windowID: String,
    resetsAt: Date?,
    now: Date
  ) -> Double? {
    guard let resetsAt, let duration = windowDurations[windowID] else { return nil }
    let left = resetsAt.timeIntervalSince(now)
    guard left > 0, left <= duration else { return nil }
    return left / duration * 100
  }
}
