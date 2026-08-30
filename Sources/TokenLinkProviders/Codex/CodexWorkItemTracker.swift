import Foundation
import TokenLinkCore

/// Pure mapping from codex app-server thread status to a watch work-item
/// state. Verified against codex-cli 0.135.0:
/// `status.type` ∈ {notLoaded, idle, systemError, active}; an active thread
/// carries `activeFlags` (e.g. waitingOnApproval, waitingOnUserInput);
/// turns report a status such as inProgress/completed/interrupted/failed.
public enum CodexWorkItemStateMapping {
  public static func state(
    statusType: String,
    activeFlags: [String] = [],
    lastTurnStatus: String? = nil
  ) -> WorkItemState {
    switch statusType {
    case "active":
      if activeFlags.contains("waitingOnApproval")
        || activeFlags.contains("waitingOnUserInput")
      {
        return .needsInput
      }
      return .running
    case "systemError":
      return .failed
    case "idle", "notLoaded":
      switch lastTurnStatus {
      case "inProgress":
        // Race between polls: turn still in flight while thread shows idle.
        return .running
      case "completed":
        return .completed
      case "interrupted", "failed":
        return .failed
      default:
        // A separately launched app-server commonly reports Desktop-owned
        // tasks as notLoaded without turns. Absence of evidence is not a
        // successful terminal event, so render it as unknown until the local
        // rollout or a later poll proves running/completed/failed.
        return .unknown
      }
    default:
      return .unknown
    }
  }
}

/// One thread as seen by a poll; `id` stays on the Mac, `name` is already
/// sanitized for the watch (≤ 12 ASCII).
public struct CodexThreadSnapshot: Equatable, Sendable {
  public let id: String
  public let name: String
  public let state: WorkItemState
  public let updatedAt: Date

  public init(id: String, name: String, state: WorkItemState, updatedAt: Date) {
    self.id = id
    self.name = name
    self.state = state
    self.updatedAt = updatedAt
  }
}

public enum CodexThreadListParseError: Error, Equatable {
  case missingResult
}

public enum CodexThreadListParser {
  public static func parse(
    data: Data,
    rolloutState: (String) -> WorkItemState? = {
      CodexRolloutActivityReader.state(atPath: $0)
    }
  ) throws -> [CodexThreadSnapshot] {
    let envelope = try JSONDecoder().decode(ThreadListEnvelope.self, from: data)
    guard let result = envelope.result else {
      throw CodexThreadListParseError.missingResult
    }
    return result.data.map { thread in
      let reportedState = CodexWorkItemStateMapping.state(
        statusType: thread.status.type,
        activeFlags: thread.status.activeFlags ?? [],
        lastTurnStatus: thread.turns?.last?.status)
      let effectiveState: WorkItemState
      if reportedState == .completed || reportedState == .unknown,
        let path = thread.path,
        let localState = rolloutState(path)
      {
        effectiveState = localState
      } else {
        effectiveState = reportedState
      }
      return CodexThreadSnapshot(
        id: thread.id,
        name: Self.displayName(
          name: thread.name, preview: thread.preview, cwd: thread.cwd),
        state: effectiveState,
        updatedAt: Date(timeIntervalSince1970: thread.updatedAt))
    }
  }

  private static func displayName(name: String?, preview: String?, cwd: String?) -> String {
    let raw = name ?? preview?.split(separator: "\n").first.map(String.init) ?? ""
    let title = WorkItem.sanitizedName(raw, fallback: "")
    if !title.isEmpty { return title }
    let workspace = cwd.map { URL(filePath: $0).lastPathComponent } ?? ""
    return WorkItem.sanitizedName(workspace, fallback: "session")
  }
}

/// Reads only the tail of a trusted Codex rollout to recover the live turn
/// state. A separately launched app-server reports Desktop-owned tasks as
/// `notLoaded`, so the rollout lifecycle is the reliable local signal.
public enum CodexRolloutActivityReader {
  private static let chunkBytes: UInt64 = 256 * 1_024
  private static let freshness: TimeInterval = 15 * 60

  public static func state(
    atPath path: String,
    now: Date = Date(),
    allowedRoot: URL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".codex/sessions")
  ) -> WorkItemState? {
    let fileURL = URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL
    let rootURL = allowedRoot.resolvingSymlinksInPath().standardizedFileURL
    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    let modified = attributes?[.modificationDate] as? Date
    let age = modified.map { now.timeIntervalSince($0) }
    guard fileURL.path.hasPrefix(rootURL.path + "/"),
      attributes?[.type] as? FileAttributeType == .typeRegular,
      let age, age >= -60, age <= freshness,
      let handle = try? FileHandle(forReadingFrom: fileURL)
    else { return nil }
    defer { try? handle.close() }

    // A long-running task can emit more than one tail chunk of tool output
    // after task_started. Walk backward until the newest lifecycle event is
    // found instead of silently turning that still-running task into unknown.
    var endOffset = (try? handle.seekToEnd()) ?? 0
    var trailingFragment = Data()
    while endOffset > 0 {
      let startOffset = endOffset > chunkBytes ? endOffset - chunkBytes : 0
      try? handle.seek(toOffset: startOffset)
      guard let chunk = try? handle.read(upToCount: Int(endOffset - startOffset)) else {
        return nil
      }
      var data = chunk
      data.append(trailingFragment)
      let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
      let completeLines = startOffset > 0 ? lines.dropFirst() : lines[...]
      for line in completeLines.reversed() {
        guard
          let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
          object["type"] as? String == "event_msg",
          let payload = object["payload"] as? [String: Any],
          let type = payload["type"] as? String
        else { continue }
        switch type {
        case "task_started": return .running
        case "task_complete": return .completed
        case "turn_aborted": return .failed
        default: continue
        }
      }
      if startOffset > 0, let firstLine = lines.first {
        trailingFragment = Data(firstLine)
      } else {
        trailingFragment = Data()
      }
      endOffset = startOffset
    }
    return nil
  }
}

private struct ThreadListEnvelope: Decodable {
  let result: ThreadListResult?
}

private struct ThreadListResult: Decodable {
  let data: [ThreadSummary]
}

private struct ThreadSummary: Decodable {
  let id: String
  let name: String?
  let preview: String?
  let cwd: String?
  let path: String?
  let updatedAt: TimeInterval
  let status: ThreadStatus
  let turns: [TurnSummary]?
}

private struct ThreadStatus: Decodable {
  let type: String
  let activeFlags: [String]?
}

private struct TurnSummary: Decodable {
  let status: String?
}

/// Polls codex app-server `thread/list`. AppModel runs this on a short session
/// lifecycle cadence, independently of the slower quota refresh cycle, and
/// feeds the results into a `WorkItemStore` via `poll(into:)`.
public struct CodexWorkItemTracker: Sendable {
  private let client: CodexAppServerClient
  private let threadLimit: Int
  private let maxThreadPages: Int
  private let startupTimeout: Duration
  private let requestTimeout: Duration

  public init(
    client: CodexAppServerClient,
    threadLimit: Int = 50,
    maxThreadPages: Int = 20,
    startupTimeout: Duration = .seconds(30),
    requestTimeout: Duration = .seconds(5)
  ) {
    self.client = client
    self.threadLimit = threadLimit
    self.maxThreadPages = maxThreadPages
    self.startupTimeout = startupTimeout
    self.requestTimeout = requestTimeout
  }

  public init(
    executable: URL,
    transport: any AppServerTransport = ProcessAppServerTransport(),
    threadLimit: Int = 50,
    maxThreadPages: Int = 20,
    startupTimeout: Duration = .seconds(30),
    requestTimeout: Duration = .seconds(5)
  ) {
    self.init(
      client: CodexAppServerClient(executable: executable, transport: transport),
      threadLimit: threadLimit,
      maxThreadPages: maxThreadPages,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout)
  }

  public func fetchThreads() async -> Result<[CodexThreadSnapshot], ProviderFailure> {
    do {
      let pages = try await client.listThreadPages(
        limit: threadLimit,
        maxPages: maxThreadPages,
        startupTimeout: startupTimeout,
        requestTimeout: requestTimeout)
      var byID: [String: CodexThreadSnapshot] = [:]
      for page in pages {
        for thread in try CodexThreadListParser.parse(data: page) {
          if let existing = byID[thread.id], existing.updatedAt >= thread.updatedAt {
            continue
          }
          byID[thread.id] = thread
        }
      }
      return .success(Array(byID.values))
    } catch AppServerTransportError.timeout {
      return .failure(
        ProviderFailure(kind: .timeout, message: "Codex app-server did not respond in time."))
    } catch AppServerTransportError.malformedResponse,
      is CodexThreadListParseError,
      is DecodingError
    {
      return .failure(
        ProviderFailure(kind: .decoding, message: "Codex thread list could not be read."))
    } catch {
      return .failure(
        ProviderFailure(kind: .process, message: "Codex app-server could not be queried."))
    }
  }

  /// One refresh-cycle tick: list threads and upsert them into the store.
  /// Returns the failure when the poll failed so the caller can log it;
  /// store contents are left untouched in that case.
  @discardableResult
  public func poll(into store: WorkItemStore) async -> ProviderFailure? {
    switch await fetchThreads() {
    case .success(let threads):
      await store.removeMissing(source: .codex, keepingIDs: Set(threads.map(\.id)))
      await store.reportActiveSessionCount(
        threads.lazy.filter { $0.state.isActive }.count)
      for thread in threads.sorted(by: { $0.updatedAt > $1.updatedAt }) {
        await store.upsert(
          id: thread.id,
          name: thread.name,
          source: .codex,
          state: thread.state,
          updatedAt: thread.updatedAt)
      }
      return nil
    case .failure(let failure):
      return failure
    }
  }
}
