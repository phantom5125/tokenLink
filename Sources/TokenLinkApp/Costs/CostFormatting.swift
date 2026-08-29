import Foundation
import TokenLinkCore

enum CostFormatting {
  static func amount(_ amount: CurrencyAmount) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .currency
    formatter.currencyCode = amount.currency
    formatter.minimumFractionDigits = amount.currency == "JPY" ? 0 : 2
    formatter.maximumFractionDigits = amount.currency == "JPY" ? 0 : 2
    return formatter.string(from: NSDecimalNumber(decimal: amount.value))
      ?? "\(amount.currency) \(amount.value)"
  }

  static func abbreviation(for provider: ProviderID) -> String {
    switch provider {
    case .openrouter: "OR"
    case .deepseek: "DS"
    case .codex: "Codex"
    case .kimi: "Kimi"
    case .claude: "Claude"
    case .minimax: "MiniMax"
    case .glm: "GLM"
    }
  }
}
