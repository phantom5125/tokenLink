import Foundation
import TokenLinkCore
import UserNotifications

/// One user-facing notification.
public struct AppNotification: Equatable, Sendable {
  public let title: String
  public let body: String

  public init(title: String, body: String) {
    self.title = title
    self.body = body
  }
}

/// Delivery channel for user notifications; injected so tests never touch the
/// real UNUserNotificationCenter.
public protocol NotificationManaging: Sendable {
  func requestAuthorizationIfNeeded() async
  func post(_ notification: AppNotification) async
}

/// Delivers through UNUserNotificationCenter. Only usable inside an app
/// bundle; `AppModel.live` falls back to `NullNotificationManager` when
/// running unpackaged (e.g. `swift run`).
public struct SystemNotificationManager: NotificationManaging {
  public init() {}

  public func requestAuthorizationIfNeeded() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  public func post(_ notification: AppNotification) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized else { return }
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.body
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    try? await center.add(request)
  }
}

public struct NullNotificationManager: NotificationManaging {
  public init() {}
  public func requestAuthorizationIfNeeded() async {}
  public func post(_ notification: AppNotification) async {}
}

/// Decides which state transitions deserve a notification. Pure and
/// latch-based: a condition notifies once and re-arms only after recovery.
public struct NotificationPolicy: Sendable {
  /// Remaining-percent threshold that triggers a low-quota alert.
  public static let lowQuotaThreshold: Double = 25

  private var latchedLowQuota: Set<String> = []
  private var latchedAuthFailure: Set<UUID> = []
  private var lastEvaluatedAt: Date?

  public init() {}

  /// - Parameters:
  ///   - nameForAccount: localized display name for an account id.
  ///   - strings: localized templates resolved by the caller's language.
  public struct Strings: Sendable {
    public var lowQuotaTitle: String
    /// `%@` provider, `%d` remaining percent.
    public var lowQuotaBody: String
    public var authFailureTitle: String
    /// `%@` provider.
    public var authFailureBody: String
    public var resetTitle: String
    /// `%@` provider, `%@` window label.
    public var resetBody: String

    public init(
      lowQuotaTitle: String, lowQuotaBody: String,
      authFailureTitle: String, authFailureBody: String,
      resetTitle: String, resetBody: String
    ) {
      self.lowQuotaTitle = lowQuotaTitle
      self.lowQuotaBody = lowQuotaBody
      self.authFailureTitle = authFailureTitle
      self.authFailureBody = authFailureBody
      self.resetTitle = resetTitle
      self.resetBody = resetBody
    }
  }

  public mutating func evaluate(
    current: [UUID: ProviderState],
    nameForAccount: (UUID) -> String,
    strings: Strings,
    now: Date
  ) -> [AppNotification] {
    var notifications: [AppNotification] = []
    defer { lastEvaluatedAt = now }

    for (accountID, state) in current {
      let name = nameForAccount(accountID)

      // Authentication/config errors: notify once until the provider recovers.
      if state.phase == .error, state.error?.kind == .authentication {
        if latchedAuthFailure.insert(accountID).inserted {
          notifications.append(
            AppNotification(
              title: strings.authFailureTitle,
              body: String(format: strings.authFailureBody, name)))
        }
      } else if state.phase == .healthy {
        latchedAuthFailure.remove(accountID)
      }

      guard let snapshot = state.snapshot else { continue }
      for window in snapshot.windows {
        // Low quota: latch until the window recovers (e.g. after a reset).
        let latchKey = "\(accountID.uuidString)-\(window.id)"
        if window.remainingPercent <= Self.lowQuotaThreshold {
          if latchedLowQuota.insert(latchKey).inserted {
            notifications.append(
              AppNotification(
                title: strings.lowQuotaTitle,
                body: String(
                  format: strings.lowQuotaBody, name,
                  Int(window.remainingPercent.rounded()))))
          }
        } else {
          latchedLowQuota.remove(latchKey)
        }

        // Reset moments that passed since the previous evaluation.
        if let lastEvaluatedAt, let resetsAt = window.resetsAt,
          resetsAt > lastEvaluatedAt, resetsAt <= now
        {
          notifications.append(
            AppNotification(
              title: strings.resetTitle,
              body: String(format: strings.resetBody, name, window.label)))
        }
      }
    }
    return notifications
  }
}
