import Foundation
import TokenLinkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Generic quota provider driven by a `ProviderSpec`. Used directly for
/// additional accounts; the per-provider structs remain as thin wrappers for
/// the default account.
public struct SpecDrivenProvider: QuotaProvider {
  public var id: ProviderID { spec.id }
  public let spec: ProviderSpec
  private let region: String?
  private let credentialAccount: String
  private let http: any HTTPClient
  private let credentials: any CredentialReader
  private let now: @Sendable () -> Date

  public init(
    spec: ProviderSpec,
    region: String? = nil,
    credentialAccount: String? = nil,
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.spec = spec
    self.region = region
    self.credentialAccount = credentialAccount ?? spec.id.rawValue
    self.http = http
    self.credentials = credentials
    self.now = now
  }

  public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
    do {
      guard let credential = try await resolveCredential() else {
        return .failure(.missingCredential(spec.missingCredentialMessage))
      }
      var request = URLRequest(url: spec.endpoint(region))
      switch spec.authStyle {
      case .bearer:
        request.setValue(
          "Bearer \(credential.value)", forHTTPHeaderField: "Authorization")
      case .rawAuthorization:
        request.setValue(credential.value, forHTTPHeaderField: "Authorization")
      }
      let response = try await http.data(
        for: request,
        policy: EndpointPolicy(allowedHosts: spec.allowedHosts))
      guard response.statusCode == 200 else {
        let authentication = response.statusCode == 401 || response.statusCode == 403
        return .failure(
          .init(
            kind: authentication ? .authentication : .network,
            message: "\(spec.displayName) returned HTTP \(response.statusCode)."))
      }
      var snapshot = try spec.parse(response.data, now())
      if snapshot.source != credential.source {
        snapshot = QuotaSnapshot(
          provider: snapshot.provider,
          planLabel: snapshot.planLabel,
          windows: snapshot.windows,
          source: credential.source,
          fetchedAt: snapshot.fetchedAt)
      }
      return .success(snapshot)
    } catch let failure as ProviderFailure {
      return .failure(failure)
    } catch {
      if let mapped = spec.errorMapper(error) {
        return .failure(mapped)
      }
      if error is DecodingError {
        return .failure(.decoding("\(spec.displayName) usage could not be read."))
      }
      return .failure(.network("\(spec.displayName) quota request failed."))
    }
  }

  /// Explicit Keychain key > CLI credential (when allowed) > allowlisted
  /// environment variables.
  private func resolveCredential() async throws -> (value: String, source: CredentialSource)? {
    if let key = try await credentials.apiKey(forAccount: credentialAccount),
      !key.isEmpty
    {
      return (key, .apiKey)
    }
    if spec.allowsCLICredential,
      let token = try await credentials.cliAccessToken(for: spec.id),
      !token.isEmpty
    {
      return (token, .cliCredential)
    }
    if let key = try await credentials.environmentAPIKey(for: spec.id),
      !key.isEmpty
    {
      return (key, .environmentVariable)
    }
    return nil
  }
}
