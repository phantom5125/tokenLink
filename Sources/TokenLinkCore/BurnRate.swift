import Foundation

/// A pace projection for one quota window: how fast the remaining percentage
/// is burning and when it reaches zero at the current rate.
public struct BurnRateEstimate: Equatable, Sendable {
  public let windowID: String
  public let percentPerHour: Double
  public let depletesAt: Date

  public init(windowID: String, percentPerHour: Double, depletesAt: Date) {
    self.windowID = windowID
    self.percentPerHour = percentPerHour
    self.depletesAt = depletesAt
  }
}

/// Pure projection from recent samples. No networking, no persistence; the
/// caller decides how samples are collected.
public enum BurnRateEstimator {
  /// Samples older than this are ignored, so a quiet night does not dilute a
  /// morning sprint.
  public static let maxSampleAge: TimeInterval = 6 * 3_600
  /// Estimates from shorter spans are noise; stay silent instead.
  public static let minSpan: TimeInterval = 30 * 60

  public struct Sample: Equatable, Sendable {
    public let date: Date
    public let remaining: Double

    public init(date: Date, remaining: Double) {
      self.date = date
      self.remaining = remaining
    }
  }

  /// Returns nil when there is not enough data or the window is not burning.
  public static func estimate(
    windowID: String,
    samples: [Sample],
    now: Date
  ) -> BurnRateEstimate? {
    let recent =
      samples
      .filter { now.timeIntervalSince($0.date) <= maxSampleAge }
      .sorted { $0.date < $1.date }
    guard let first = recent.first, let last = recent.last else { return nil }
    let span = last.date.timeIntervalSince(first.date)
    guard span >= minSpan else { return nil }
    let burned = first.remaining - last.remaining
    guard burned > 0 else { return nil }
    let ratePerHour = burned / (span / 3_600)
    let hoursLeft = last.remaining / ratePerHour
    return BurnRateEstimate(
      windowID: windowID,
      percentPerHour: ratePerHour,
      depletesAt: last.date.addingTimeInterval(hoursLeft * 3_600))
  }
}
