import Foundation

public enum CredentialSource: String, Codable, Sendable {
  case apiKey
  case cliCredential
  case environmentVariable
  case localAppServer
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let usedPercent: Double?
  public let remainingPercent: Double
  public let remainingCount: Double?
  public let limitCount: Double?
  public let resetsAt: Date?

  public init(
    id: String,
    label: String,
    usedPercent: Double?,
    remainingPercent: Double,
    remainingCount: Double?,
    limitCount: Double?,
    resetsAt: Date?
  ) {
    self.id = id
    self.label = label
    self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
    self.remainingPercent = min(100, max(0, remainingPercent))
    self.remainingCount = remainingCount
    self.limitCount = limitCount
    self.resetsAt = resetsAt
  }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
  public let provider: ProviderID
  public let planLabel: String?
  public let windows: [QuotaWindow]
  public let source: CredentialSource
  public let fetchedAt: Date

  public var mostConstrainedWindow: QuotaWindow? {
    windows.min { $0.remainingPercent < $1.remainingPercent }
  }

  public init(
    provider: ProviderID,
    planLabel: String?,
    windows: [QuotaWindow],
    source: CredentialSource,
    fetchedAt: Date
  ) {
    self.provider = provider
    self.planLabel = planLabel
    self.windows = windows
    self.source = source
    self.fetchedAt = fetchedAt
  }
}
