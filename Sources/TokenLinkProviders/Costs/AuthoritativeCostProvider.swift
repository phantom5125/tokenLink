import Foundation
import TokenLinkCore

public protocol AuthoritativeCostProvider: Sendable {
  var id: ProviderID { get }

  func fetch() async -> Result<AuthoritativeCostSnapshot, ProviderFailure>
}

public struct AccountCostProvider: Sendable {
  public let accountID: UUID
  public let provider: any AuthoritativeCostProvider

  public init(accountID: UUID, provider: any AuthoritativeCostProvider) {
    self.accountID = accountID
    self.provider = provider
  }
}

struct LosslessDecimal: Decodable, Sendable {
  let value: Decimal

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if (try? container.decode(Bool.self)) != nil {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "A monetary value cannot be a Boolean.")
    }

    let decoded: Decimal?
    if let decimal = try? container.decode(Decimal.self) {
      decoded = decimal
    } else if let string = try? container.decode(String.self), !string.isEmpty {
      decoded = Decimal(
        string: string,
        locale: Locale(identifier: "en_US_POSIX"))
    } else {
      decoded = nil
    }

    guard var decoded, !NSDecimalIsNotANumber(&decoded) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected a finite decimal number or numeric string.")
    }
    self.value = decoded
  }
}

enum AuthoritativeCostSupport {
  static func credential(
    account: String,
    reader: any CredentialReader,
    providerName: String
  ) async -> Result<String, ProviderFailure> {
    do {
      guard let key = try await reader.apiKey(forAccount: account), !key.isEmpty else {
        return .failure(
          .missingCredential("Configure an explicit \(providerName) API key."))
      }
      return .success(key)
    } catch let failure as ProviderFailure {
      return .failure(failure)
    } catch {
      return .failure(.network("\(providerName) credential could not be read."))
    }
  }

  static func request(url: URL, bearerToken: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    return request
  }

  static func responseFailure(
    statusCode: Int,
    providerName: String,
    sourceName: String
  ) -> ProviderFailure {
    let kind: ProviderErrorKind =
      statusCode == 401 || statusCode == 403 ? .authentication : .network
    return ProviderFailure(
      kind: kind,
      message: "\(providerName) \(sourceName) returned HTTP \(statusCode).")
  }

  static func aggregate(_ failures: [ProviderFailure]) -> ProviderFailure {
    precondition(!failures.isEmpty)
    if failures.allSatisfy({ $0.kind == .authentication }) {
      return failures[0]
    }
    return failures.first { $0.kind == .decoding }
      ?? failures.first { $0.kind != .authentication }
      ?? failures[0]
  }
}
