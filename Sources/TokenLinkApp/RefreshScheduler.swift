import Foundation

@MainActor
public final class RefreshScheduler {
  public let minutes: Int
  public let interval: Duration
  private var task: Task<Void, Never>?

  public init(minutes: Int) {
    let supported = [1, 2, 5, 15, 30]
    self.minutes = supported.contains(minutes) ? minutes : 5
    self.interval = .seconds(self.minutes * 60)
  }

  public func start(action: @escaping @MainActor @Sendable () async -> Void) {
    stop()
    let interval = interval
    task = Task { @MainActor in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        await action()
      }
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
  }

  deinit {
    task?.cancel()
  }
}
