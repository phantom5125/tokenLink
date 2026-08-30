import Foundation

/// A small thread-safe broadcast source whose streams can be cancelled and
/// recreated independently. `AsyncStream` itself is not reusable after its
/// sole consumer is cancelled, which matters when Bluetooth bindings restart.
final class AsyncEventHub<Element: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

  func stream(
    bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(8)
  ) -> AsyncStream<Element> {
    let identifier = UUID()
    return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
      lock.lock()
      continuations[identifier] = continuation
      lock.unlock()
      continuation.onTermination = { @Sendable [weak self] _ in
        self?.remove(identifier)
      }
    }
  }

  func yield(_ element: Element) {
    lock.lock()
    let current = Array(continuations.values)
    lock.unlock()
    for continuation in current {
      continuation.yield(element)
    }
  }

  func finish() {
    lock.lock()
    let current = Array(continuations.values)
    continuations.removeAll()
    lock.unlock()
    for continuation in current {
      continuation.finish()
    }
  }

  private func remove(_ identifier: UUID) {
    lock.lock()
    continuations.removeValue(forKey: identifier)
    lock.unlock()
  }
}
