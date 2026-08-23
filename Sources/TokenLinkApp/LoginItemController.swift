import Foundation
import ServiceManagement

public enum LoginItemState: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
}

/// 登录项控制的抽象，测试注入 fake，不触碰真实 SMAppService。
public protocol LoginItemControlling: Sendable {
    var status: LoginItemState { get }
    @discardableResult func register() throws -> LoginItemState
    func unregister() throws
}

public struct LoginItemController: LoginItemControlling {
    public init() {}

    public var status: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .notRegistered
        }
    }

    /// `.requiresApproval` 不是失败：注册可能已排队，等用户在系统设置里批准。
    @discardableResult
    public func register() throws -> LoginItemState {
        try SMAppService.mainApp.register()
        return status
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
