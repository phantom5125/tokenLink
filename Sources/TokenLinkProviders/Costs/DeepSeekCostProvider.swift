import Foundation
import TokenLinkCore

public struct DeepSeekCostProvider: AuthoritativeCostProvider {
  public let id: ProviderID = .deepseek

  private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!
  private static let policy = EndpointPolicy(allowedHosts: ["api.deepseek.com"])

  private let credentialAccount: String
  private let http: any HTTPClient
  private let credentials: any CredentialReader
  private let now: @Sendable () -> Date

  public init(
    credentialAccount: String = ProviderID.deepseek.rawValue,
    http: any HTTPClient,
    credentials: any CredentialReader,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.credentialAccount = credentialAccount
    self.http = http
    self.credentials = credentials
    self.now = now
  }

  public func fetch() async -> Result<AuthoritativeCostSnapshot, ProviderFailure> {
    let credential = await AuthoritativeCostSupport.credential(
      account: credentialAccount,
      reader: credentials,
      providerName: "DeepSeek")
    let key: String
    switch credential {
    case .success(let value):
      key = value
    case .failure(let failure):
      return .failure(failure)
    }

    do {
      let response = try await http.data(
        for: AuthoritativeCostSupport.request(
          url: Self.balanceURL,
          bearerToken: key),
        policy: Self.policy)
      guard response.statusCode == 200 else {
        return .failure(
          AuthoritativeCostSupport.responseFailure(
            statusCode: response.statusCode,
            providerName: "DeepSeek",
            sourceName: "balance"))
      }
      let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: response.data)
      return .success(
        AuthoritativeCostSnapshot(
          provider: id,
          balances: decoded.balanceInfos.map {
            AccountBalance(currency: $0.currency, available: $0.totalBalance.value)
          },
          isAvailable: decoded.isAvailable,
          fetchedAt: now()))
    } catch is DecodingError {
      return .failure(.decoding("DeepSeek balance could not be read."))
    } catch {
      return .failure(.network("DeepSeek balance request failed."))
    }
  }
}

private struct DeepSeekBalanceResponse: Decodable {
  let isAvailable: Bool
  let balanceInfos: [DeepSeekBalanceInfo]

  private enum CodingKeys: String, CodingKey {
    case isAvailable = "is_available"
    case balanceInfos = "balance_infos"
  }
}

private struct DeepSeekBalanceInfo: Decodable {
  let currency: String
  let totalBalance: LosslessDecimal

  private enum CodingKeys: String, CodingKey {
    case currency
    case totalBalance = "total_balance"
  }
}
