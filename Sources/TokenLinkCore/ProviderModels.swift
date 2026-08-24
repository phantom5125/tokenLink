public enum ProviderID: String, Codable, CaseIterable, Sendable {
  case codex
  case kimi
  case minimax
  case glm
  case claude
}

public struct ProviderDescriptor: Equatable, Sendable {
  public let id: ProviderID
  public let displayName: String

  public init(id: ProviderID, displayName: String) {
    self.id = id
    self.displayName = displayName
  }
}
