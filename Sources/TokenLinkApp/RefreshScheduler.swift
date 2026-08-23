import Foundation

/// 周期刷新调度：只支持 1/2/5/15/30 分钟，其它值回落到 5 分钟。
public struct RefreshScheduler: Sendable {
    public static let allowedMinutes = [1, 2, 5, 15, 30]

    public let minutes: Int
    public var interval: Duration { .seconds(minutes * 60) }

    public init(minutes: Int) {
        self.minutes = Self.allowedMinutes.contains(minutes) ? minutes : 5
    }

    /// 返回一个可取消的周期任务；调用方负责持有与取消。
    public func start(_ action: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let interval = interval
        return Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }
}
