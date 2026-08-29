public enum ProviderID: String, Codable, CaseIterable, Sendable {
  case codex
  case kimi
  case minimax
  case glm
  case claude
  case openrouter
  case deepseek
}

public struct ProviderCapability: OptionSet, Equatable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let quota = Self(rawValue: 1 << 0)
  public static let authoritativeCost = Self(rawValue: 1 << 1)
  public static let localCostEstimate = Self(rawValue: 1 << 2)
}

public struct ProviderDescriptor: Equatable, Sendable {
  public let id: ProviderID
  public let displayName: String

  public init(id: ProviderID, displayName: String) {
    self.id = id
    self.displayName = displayName
  }
}
