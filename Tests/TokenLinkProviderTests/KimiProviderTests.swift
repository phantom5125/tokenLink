import Foundation
import Testing

@testable import TokenLinkCore
@testable import TokenLinkProviders

@Test func parsesKimiWeeklyAndFiveHourWindows() throws {
  let data = try Fixture.load("kimi-usages.json")
  let snapshot = try KimiParser.parse(
    data: data,
    fetchedAt: Date(timeIntervalSince1970: 1_787_130_000),
    source: .apiKey)
  #expect(snapshot.provider == .kimi)
  #expect(snapshot.planLabel == "BASIC")
  #expect(snapshot.windows.map(\.id) == ["weekly", "5h"])
  #expect(snapshot.windows[0].remainingPercent == 75)
  #expect(snapshot.windows[1].remainingPercent == 60)
}

private struct StubHTTPClient: HTTPClient {
  let data: Data
  let statusCode: Int
  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    HTTPResponse(data: data, statusCode: statusCode)
  }
}

private struct StubCredentials: CredentialReader {
  let apiKey: String?
  let cliToken: String?
  func apiKey(for provider: ProviderID) async throws -> String? { apiKey }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { cliToken }
}

@Test func kimiProviderUsesExplicitAPIKeyWhenPresent() async throws {
  let http = StubHTTPClient(data: try Fixture.load("kimi-usages.json"), statusCode: 200)
  let credentials = StubCredentials(apiKey: "explicit-token", cliToken: "cli-token")
  let provider = KimiProvider(http: http, credentials: credentials)
  let result = await provider.fetch()
  let snapshot = try result.get()
  #expect(snapshot.source == .apiKey)
  #expect(snapshot.windows.map(\.id) == ["weekly", "5h"])
}

@Test func kimiProviderMapsAuthenticationFailure() async {
  let http = StubHTTPClient(data: Data(), statusCode: 401)
  let credentials = StubCredentials(apiKey: "expired", cliToken: nil)
  let provider = KimiProvider(http: http, credentials: credentials)
  let result = await provider.fetch()
  switch result {
  case .success: Issue.record("expected failure")
  case .failure(let failure):
    #expect(failure.kind == .authentication)
  }
}

@Test func kimiProviderReportsMissingCredentialWhenEmpty() async {
  let http = StubHTTPClient(data: Data(), statusCode: 200)
  let credentials = StubCredentials(apiKey: nil, cliToken: nil)
  let provider = KimiProvider(http: http, credentials: credentials)
  let result = await provider.fetch()
  switch result {
  case .success: Issue.record("expected failure")
  case .failure(let failure):
    #expect(failure.kind == .missingCredential)
  }
}

@Test func kimiCLICredentialReaderReturnsTokenForValidFile() throws {
  let home = try makeTemporaryHome()
  defer { try? FileManager.default.removeItem(at: home) }
  try writeKimiCredentials(
    in: home,
    json: """
      {"access_token":"abc","expires_at":"2099-01-01T00:00:00Z"}
      """)
  let reader = KimiCLICredentialReader(homeDirectory: home)
  #expect(try reader.currentAccessToken() == "abc")
}

@Test func kimiCLICredentialReaderReturnsNilForExpiredToken() throws {
  let home = try makeTemporaryHome()
  defer { try? FileManager.default.removeItem(at: home) }
  try writeKimiCredentials(
    in: home,
    json: """
      {"access_token":"stale","expires_at":"2000-01-01T00:00:00Z"}
      """)
  let reader = KimiCLICredentialReader(homeDirectory: home)
  #expect(try reader.currentAccessToken() == nil)
}

@Test func kimiCLICredentialReaderIgnoresSiblingFiles() throws {
  let home = try makeTemporaryHome()
  defer { try? FileManager.default.removeItem(at: home) }
  // Sibling in the same directory
  let sibling = home.appending(path: ".kimi-code/credentials/kimi-code.json.bak")
  try FileManager.default.createDirectory(
    at: sibling.deletingLastPathComponent(),
    withIntermediateDirectories: true)
  try Data("{\"access_token\":\"sibling\"}".utf8).write(to: sibling)
  // Sibling in a parallel directory
  let altDir = home.appending(path: ".kimi/credentials")
  try FileManager.default.createDirectory(at: altDir, withIntermediateDirectories: true)
  try Data("{\"access_token\":\"alt-path\"}".utf8).write(
    to: altDir.appending(path: "kimi-code.json"))
  let reader = KimiCLICredentialReader(homeDirectory: home)
  #expect(throws: (any Error).self) {
    _ = try reader.currentAccessToken()
  }
}

@Test func kimiCLICredentialReaderNeverExposesRefreshToken() throws {
  let home = try makeTemporaryHome()
  defer { try? FileManager.default.removeItem(at: home) }
  try writeKimiCredentials(
    in: home,
    json: """
      {"access_token":"abc","refresh_token":"hidden","expires_at":"2099-01-01T00:00:00Z"}
      """)
  let reader = KimiCLICredentialReader(homeDirectory: home)
  let token = try #require(try reader.currentAccessToken())
  #expect(token == "abc")
  #expect(!token.contains("hidden"))
}

private func makeTemporaryHome() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "kimi-home-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func writeKimiCredentials(in home: URL, json: String) throws {
  let dir = home.appending(path: ".kimi-code/credentials")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  try Data(json.utf8).write(to: dir.appending(path: "kimi-code.json"))
}
