import Foundation

public enum MenuBarCostMetric: Codable, Equatable, Sendable {
  case none
  case localEstimate(ProviderID)
  case authoritativeBalance(accountID: UUID, currency: String)
}
