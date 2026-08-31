import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

@Test func bundledPriceCatalogLoadsReviewedEntries() throws {
  // Catches shipping an absent, stale, or partially decoded catalog resource.
  let catalog = try PriceCatalog.bundled()

  #expect(catalog.version == "2026-08-31.1")
  #expect(catalog.effectiveDate == Date(timeIntervalSince1970: 1_788_134_400))
  #expect(catalog.entries.count == 10)
  #expect(
    catalog.entry(provider: .codex, modelID: "gpt-5.6-sol")?.cacheWritePerMillion
      == Decimal(string: "5.00"))
  #expect(
    catalog.entry(provider: .codex, modelID: "gpt-5.6-terra")?.fastMultiplier
      == Decimal(string: "2.0"))
  #expect(
    catalog.entry(provider: .codex, modelID: "gpt-5.6-luna")?.outputPerMillion
      == Decimal(string: "1.20"))
  #expect(
    catalog.entry(provider: .codex, modelID: "gpt-5.5")?.outputPerMillion
      == Decimal(string: "30.00"))
  #expect(
    catalog.entry(provider: .claude, modelID: "claude-sonnet-5")?
      .cacheWriteFiveMinutePerMillion == Decimal(string: "2.50"))
  #expect(
    catalog.entry(provider: .kimi, modelID: "kimi-k3")?.cacheReadPerMillion
      == Decimal(string: "0.30"))
}

@Test func priceCatalogResolvesOnlyExplicitAliases() throws {
  // Catches prefix matching a new upstream model to an older model's price.
  let catalog = try PriceCatalog.bundled()

  #expect(
    catalog.entry(provider: .kimi, modelID: "kimi-code/k3")?.modelID
      == "kimi-k3")
  #expect(
    catalog.entry(provider: .claude, modelID: "claude-haiku-4-5")?.modelID
      == "claude-haiku-4-5-20251001")
  #expect(
    catalog.entry(provider: .codex, modelID: "gpt-5.6")?.modelID
      == "gpt-5.6-sol")
  #expect(catalog.entry(provider: .codex, modelID: "gpt-5.5-future") == nil)
  #expect(catalog.entry(provider: .claude, modelID: "MiniMax-M3") == nil)
}

@Test func priceCatalogUsesFirstPartyHTTPSReferences() throws {
  // Catches estimates becoming detached from an auditable first-party source.
  let catalog = try PriceCatalog.bundled()
  let allowedHosts: Set<String> = [
    "developers.openai.com",
    "platform.claude.com",
    "platform.kimi.ai",
  ]

  for entry in catalog.entries {
    #expect(entry.sourceURL.scheme == "https")
    #expect(entry.sourceURL.host.map(allowedHosts.contains) == true)
  }
}
