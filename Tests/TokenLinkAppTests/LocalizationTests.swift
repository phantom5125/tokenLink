import Foundation
import Testing

@testable import TokenLinkApp

private actor LocalizationStubRefresher: AppRefreshing {
  func refresh() async {}
}

@Test func catalogCoversEveryKeyInEveryLanguage() {
  for key in L10n.Key.allCases {
    for language in AppLanguage.allCases {
      let text = L10n.text(key, language: language)
      #expect(!text.isEmpty, "Missing translation for \(key.rawValue) in \(language.rawValue)")
      #expect(text != key.rawValue, "Untranslated key \(key.rawValue) in \(language.rawValue)")
    }
  }
}

@Test func languageResolutionPrefersExplicitChoiceThenSystem() {
  #expect(
    AppLanguage.resolve(preference: "ja", preferredLanguages: ["zh-Hans"]) == .japanese)
  #expect(
    AppLanguage.resolve(preference: nil, preferredLanguages: ["zh-Hans-CN"])
      == .simplifiedChinese)
  #expect(
    AppLanguage.resolve(preference: nil, preferredLanguages: ["en-US", "ja-JP"])
      == .japanese)
  #expect(AppLanguage.resolve(preference: nil, preferredLanguages: ["en-US"]) == .english)
  #expect(
    AppLanguage.resolve(preference: "bogus", preferredLanguages: ["en-US"]) == .english)
}

@MainActor @Test func appLanguagePersistsThroughConfigurationStore() throws {
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let store = ConfigurationStore(directory: directory)
  let model = AppModel(
    refresher: LocalizationStubRefresher(), configurationStore: store)

  #expect(model.currentLanguage == AppLanguage.resolve(preference: nil))
  try model.setAppLanguage(AppLanguage.japanese.rawValue)
  #expect(model.currentLanguage == .japanese)
  try model.setAppLanguage(String?.none)
  #expect(model.configuration.appLanguage == nil)
}
