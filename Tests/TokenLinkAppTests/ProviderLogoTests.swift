import Testing
import TokenLinkCore

@testable import TokenLinkApp

@Test func everyProviderLogoLoadsFromResources() {
  for provider in ProviderID.allCases {
    #expect(ProviderLogo.image(for: provider) != nil)
  }
}
