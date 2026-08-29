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
  @MainActor func openCodexThread(_ threadID: String) -> Bool
  @MainActor func activateCodexDesktop() -> Bool
}

/// Opens the same `codex://threads/<id>` deep link that Codex Desktop's own
/// "Copy App Link" action emits. Activation remains a compatibility fallback
/// for older builds or malformed/missing thread identifiers.
public struct SystemCodexDesktopActivator: CodexDesktopActivating {
  public init() {}

  @MainActor public func openCodexThread(_ threadID: String) -> Bool {
    guard runningCodex != nil, isSafeThreadID(threadID),
      let url = URL(string: "codex://threads/\(threadID)")
    else { return false }
    return NSWorkspace.shared.open(url)
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

  public func handle(_ command: WatchCommand) async {
    switch command {
    case .refresh:
      await onRefresh()
    case .focus(let slot):
      await focus(slot: slot)
    }
  }

  private func focus(slot: Int) async {
    guard let session = await sessionProvider(slot) else {
      await record("Watch focus ignored: no work item in slot \(slot)")
      return
    }
    guard session.source == .codex else {
      await record("Watch focus ignored: slot \(slot) is not a Codex session")
      return
    }
    if let threadID = session.threadID,
      await activator.openCodexThread(threadID)
    {
      await record("Watch focus opened Codex session")
      return
    }
    guard await activator.activateCodexDesktop() else {
      await record("Watch focus failed: Codex Desktop is not running")
      return
    }
    await record("Watch focus activated Codex Desktop (session link unavailable)")
  }
}
