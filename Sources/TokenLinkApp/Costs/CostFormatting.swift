import Foundation
import TokenLinkCore

enum CostFormatting {
  static func amount(_ amount: CurrencyAmount, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale(for: language)
    formatter.numberStyle = .currency
    formatter.currencyCode = amount.currency
    formatter.minimumFractionDigits = amount.currency == "JPY" ? 0 : 2
    formatter.maximumFractionDigits = amount.currency == "JPY" ? 0 : 2
    return formatter.string(from: NSDecimalNumber(decimal: amount.value))
      ?? "\(amount.currency) \(amount.value)"
  }

  static func preciseAmount(_ amount: CurrencyAmount, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale(for: language)
    formatter.numberStyle = .currency
    formatter.currencyCode = amount.currency
    formatter.minimumFractionDigits = amount.currency == "JPY" ? 0 : 2
    formatter.maximumFractionDigits = amount.currency == "JPY" ? 4 : 6
    return formatter.string(from: NSDecimalNumber(decimal: amount.value))
      ?? "\(amount.currency) \(amount.value)"
  }

  static func tokenCount(_ value: Int, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale(for: language)
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  static func decimal(_ value: Decimal, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale(for: language)
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
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

  private static func locale(for language: AppLanguage) -> Locale {
    switch language {
    case .english: Locale(identifier: "en_US")
    case .simplifiedChinese: Locale(identifier: "zh_CN")
    case .japanese: Locale(identifier: "ja_JP")
    }
  }
}
