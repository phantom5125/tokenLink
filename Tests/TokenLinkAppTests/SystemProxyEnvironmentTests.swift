import Foundation
import Testing

@testable import TokenLinkApp

@Test func proxyEnvironmentFromHTTPSProxy() {
  let settings: [String: Any] = [
    "HTTPSEnable": 1,
    "HTTPSProxy": "127.0.0.1",
    "HTTPSPort": 7892,
  ]
  let env = SystemProxyEnvironment.environment(from: settings)
  #expect(env["HTTPS_PROXY"] == "http://127.0.0.1:7892")
  #expect(env["https_proxy"] == "http://127.0.0.1:7892")
  #expect(env["HTTP_PROXY"] == nil)
}

@Test func proxyEnvironmentFallsBackToSOCKS() {
  let settings: [String: Any] = [
    "SOCKSEnable": 1,
    "SOCKSProxy": "127.0.0.1",
    "SOCKSPort": 1080,
  ]
  let env = SystemProxyEnvironment.environment(from: settings)
  #expect(env["ALL_PROXY"] == "socks5://127.0.0.1:1080")
  #expect(env["HTTPS_PROXY"] == nil)
}

@Test func proxyEnvironmentEmptyWhenDisabled() {
  #expect(SystemProxyEnvironment.environment(from: [:]).isEmpty)
  #expect(
    SystemProxyEnvironment.environment(from: [
      "HTTPSEnable": 0,
      "HTTPSProxy": "127.0.0.1",
      "HTTPSPort": 7892,
    ]).isEmpty)
}
