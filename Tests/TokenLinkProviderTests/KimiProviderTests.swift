import Foundation
import Testing
import TokenLinkCore

@testable import TokenLinkProviders

private struct KimiCredentials: CredentialReader {
  let apiKeyValue: String?
  let cliTokenValue: String?

  func apiKey(for provider: ProviderID) async throws -> String? { apiKeyValue }
  func cliAccessToken(for provider: ProviderID) async throws -> String? { cliTokenValue }
}

private actor KimiHTTPClient: HTTPClient {
  let response: HTTPResponse
  private(set) var request: URLRequest?

  init(response: HTTPResponse) { self.response = response }

  func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
    _ = try policy.validate(try #require(request.url))
    self.request = request
    return response
  }
}

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

@Test func kimiCLIReaderUsesOnlyDocumentedCredentialFile() async throws {
  let root = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  let credentialDirectory = root.appending(
    path: ".kimi-code/credentials", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(
    at: credentialDirectory, withIntermediateDirectories: true)
  let credential = credentialDirectory.appending(path: "kimi-code.json")
  try Data(
    #"{"access_token":"safe-token","expires_at":4102444800,"refresh_token":"never-return-this"}"#
      .utf8
  )
  .write(to: credential)
  try Data(#"{"access_token":"browser-token","expires_at":4102444800}"#.utf8)
    .write(to: root.appending(path: "browser-cookies.json"))
  defer { try? FileManager.default.removeItem(at: root) }

  let reader = KimiCLICredentialReader(
    homeURL: root,
    now: { Date(timeIntervalSince1970: 1_787_130_000) })
  #expect(try await reader.accessToken() == "safe-token")
}

@Test func kimiCLIReaderRejectsExpiredToken() async throws {
  let root = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  let credentialDirectory = root.appending(
    path: ".kimi-code/credentials", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(
    at: credentialDirectory, withIntermediateDirectories: true)
  try Data(#"{"access_token":"expired","expires_at":100}"#.utf8)
    .write(to: credentialDirectory.appending(path: "kimi-code.json"))
  defer { try? FileManager.default.removeItem(at: root) }

  let reader = KimiCLICredentialReader(
    homeURL: root,
    now: { Date(timeIntervalSince1970: 200) })
  #expect(try await reader.accessToken() == nil)
}

@Test func kimiProviderPrefersExplicitAPIKey() async throws {
  let http = KimiHTTPClient(
    response: HTTPResponse(
      data: try Fixture.load("kimi-usages.json"),
      statusCode: 200))
  let provider = KimiProvider(
    http: http,
    credentials: KimiCredentials(apiKeyValue: "explicit-key", cliTokenValue: "cli-token"),
    now: { Date(timeIntervalSince1970: 1_787_130_000) })

  let result = await provider.fetch()
  let snapshot = try result.get()
  #expect(snapshot.source == .apiKey)
  #expect(await http.request?.value(forHTTPHeaderField: "Authorization") == "Bearer explicit-key")
}
