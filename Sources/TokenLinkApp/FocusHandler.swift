import AppKit
import Foundation
import TokenLinkCore
import TokenLinkDevice

/// The Mac-side record a watch work item maps to. Only Codex sessions are
/// focusable in protocol v2.
public struct FocusSession: Equatable, Sendable {
  public let slot: Int
  public let source: ProviderID
  public let threadID: String?

  public init(slot: Int, source: ProviderID, threadID: String? = nil) {
    self.slot = slot
    self.source = source
    self.threadID = threadID
  }
}

public protocol CodexDesktopActivating: Sendable {
  @MainActor func openCodexThread(_ threadID: String) async -> Bool
  @MainActor func activateCodexDesktop() -> Bool
}

/// Opens the same `codex://threads/<id>` deep link that Codex Desktop's own
/// "Copy App Link" action emits. Activation remains a compatibility fallback
/// for older builds or malformed/missing thread identifiers.
public struct SystemCodexDesktopActivator: CodexDesktopActivating {
  public init() {}

  @MainActor public func openCodexThread(_ threadID: String) async -> Bool {
    guard let runningCodex, let applicationURL = runningCodex.bundleURL,
      isSafeThreadID(threadID),
      let url = URL(string: "codex://threads/\(threadID)")
    else { return false }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    return await withCheckedContinuation { continuation in
      // Target the currently running Codex bundle explicitly. A bare
      // `NSWorkspace.open(url)` only confirms LaunchServices accepted the
      // scheme; it can report success without proving which app received it.
      NSWorkspace.shared.open(
        [url],
        withApplicationAt: applicationURL,
        configuration: configuration
      ) { application, error in
        if let application, error == nil {
          _ = application.activate(options: [.activateAllWindows])
          continuation.resume(returning: true)
        } else {
          continuation.resume(returning: false)
        }
      }
    }
  }

  @MainActor public func activateCodexDesktop() -> Bool {
    runningCodex?.activate(options: [.activateAllWindows]) ?? false
  }

  @MainActor private var runningCodex: NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == "com.openai.codex" || $0.localizedName == "Codex"
    })
  }

  private func isSafeThreadID(_ value: String) -> Bool {
    !value.isEmpty
      && value.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
      }
  }
}

public enum WatchFocusOutcome: String, Equatable, Sendable {
  case openedThread
  case activatedFallback
  case noWorkItem
  case unsupportedProvider
  case desktopUnavailable

  public var succeeded: Bool {
    self == .openedThread
  }
}

/// Routes watch commands to Mac-side actions. AppModel owns an instance and
/// feeds it `DeviceBridge.commandStream`; session lookup and event recording
/// are injected so the handler stays testable without AppKit or BLE.
public struct FocusHandler: Sendable {
  public typealias SessionProvider = @Sendable (Int) async -> FocusSession?
  public typealias EventSink = @Sendable (String) async -> Void

  private let sessionProvider: SessionProvider
  private let activator: any CodexDesktopActivating
  private let onRefresh: @Sendable () async -> Void
  private let record: EventSink

  public init(
    sessionProvider: @escaping SessionProvider,
    activator: any CodexDesktopActivating,
    onRefresh: @escaping @Sendable () async -> Void = {},
    record: @escaping EventSink = { _ in }
  ) {
    self.sessionProvider = sessionProvider
    self.activator = activator
    self.onRefresh = onRefresh
    self.record = record
  }

  @discardableResult
  public func handle(_ command: WatchCommand) async -> WatchFocusOutcome? {
    switch command {
    case .refresh:
      await onRefresh()
      return nil
    case .focus(let slot):
      return await focus(slot: slot)
    }
  }

  private func focus(slot: Int) async -> WatchFocusOutcome {
    guard let session = await sessionProvider(slot) else {
      await record("Watch focus ignored: no work item in slot \(slot)")
      return .noWorkItem
    }
    guard session.source == .codex else {
      await record("Watch focus ignored: slot \(slot) is not a Codex session")
      return .unsupportedProvider
    }
    if let threadID = session.threadID,
      await activator.openCodexThread(threadID)
    {
      await record("Watch focus opened Codex session")
      return .openedThread
    }
    guard await activator.activateCodexDesktop() else {
      await record("Watch focus failed: Codex Desktop is not running")
      return .desktopUnavailable
    }
    await record("Watch focus activated Codex Desktop (session link unavailable)")
    return .activatedFallback
  }
}
