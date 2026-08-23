import Foundation
import Testing

@testable import TokenLinkProviders

@Test func endpointPolicyRejectsPlainHTTPAndUnknownHosts() throws {
  let policy = EndpointPolicy(allowedHosts: ["api.kimi.com"])
  #expect(throws: ProviderHostError.self) {
    try policy.validate(URL(string: "http://api.kimi.com/coding/v1/usages")!)
  }
  #expect(throws: ProviderHostError.self) {
    try policy.validate(URL(string: "https://example.com/coding/v1/usages")!)
  }
  #expect(
    try policy.validate(URL(string: "https://api.kimi.com/coding/v1/usages")!).host
      == "api.kimi.com")
}
