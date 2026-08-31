import Testing
import TokenLinkCore
import TokenLinkProviders

@testable import TokenLinkApp

@Test func everyQuotaProviderLogoLoadsFromResources() {
  // Cost-only providers use the explicit SF Symbol fallback in ProviderMark.
  for provider in ProviderRegistry.quotaProviderIDs {
    #expect(ProviderLogo.image(for: provider) != nil)
  }
}
