import ServiceManagement

public enum LoginItemState: Equatable, Sendable {
  case disabled
  case enabled
  case requiresApproval
  case unavailable
}

@MainActor
public protocol LoginItemControlling: AnyObject {
  var state: LoginItemState { get }
  func setEnabled(_ enabled: Bool) throws -> LoginItemState
}

@MainActor
public final class LoginItemController: LoginItemControlling {
  private let service: SMAppService

  public init(service: SMAppService = .mainApp) {
    self.service = service
  }

  public var state: LoginItemState {
    switch service.status {
    case .notRegistered: .disabled
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .unavailable
    @unknown default: .unavailable
    }
  }

  public func setEnabled(_ enabled: Bool) throws -> LoginItemState {
    if enabled {
      try service.register()
    } else {
      try service.unregister()
    }
    return state
  }
}
