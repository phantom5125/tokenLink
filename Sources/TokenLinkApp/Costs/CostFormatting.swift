import Foundation
import TokenLinkCore

enum CostFormatting {
  static func amount(_ amount: CurrencyAmount, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale =
      switch language {
      case .english: Locale(identifier: "en_US")
      case .simplifiedChinese: Locale(identifier: "zh_CN")
      case .japanese: Locale(identifier: "ja_JP")
      }
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
