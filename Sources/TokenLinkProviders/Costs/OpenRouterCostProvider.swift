import Foundation
import TokenLinkCore

public struct OpenRouterCostProvider: AuthoritativeCostProvider {
  public let id: ProviderID = .openrouter

  private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
  private static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!
  private static let policy = EndpointPolicy(allowedHosts: ["openrouter.ai"])

  private let credentialAccount: String
  private let http: any HTTPClient
  private let credentials: any CredentialReader
  private let now: @Sendable () -> Date

  public init(
    credentialAccount: String = ProviderID.openrouter.rawValue,
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
      providerName: "OpenRouter")
    let key: String
    switch credential {
    case .success(let value):
      key = value
    case .failure(let failure):
      return .failure(failure)
    }

    async let creditsResult = fetchCredits(key: key)
    async let keyResult = fetchKey(key: key)
    let (credits, currentKey) = await (creditsResult, keyResult)

    var balances: [AccountBalance] = []
    var periodSpend: [ProviderPeriodSpend] = []
    var warnings: [CostWarning] = []
    var failures: [ProviderFailure] = []

    switch credits {
    case .success(let balance):
      balances = [balance]
    case .failure(let failure):
      failures.append(failure)
      warnings.append(.partialSource("credits"))
    }

    switch currentKey {
    case .success(let value):
      if balances.isEmpty, let balance = value.balance {
        balances = [balance]
      }
      periodSpend = value.periodSpend
    case .failure(let failure):
      failures.append(failure)
      warnings.append(.partialSource("key"))
    }

    guard !balances.isEmpty || !periodSpend.isEmpty else {
      return .failure(AuthoritativeCostSupport.aggregate(failures))
    }
    if failures.isEmpty {
      warnings.removeAll()
    }
    return .success(
      AuthoritativeCostSnapshot(
        provider: id,
        balances: balances,
        periodSpend: periodSpend,
        warnings: warnings,
        fetchedAt: now()))
  }

  private func fetchCredits(key: String) async -> Result<AccountBalance, ProviderFailure> {
    do {
      let response = try await http.data(
        for: AuthoritativeCostSupport.request(
          url: Self.creditsURL,
          bearerToken: key),
        policy: Self.policy)
      guard response.statusCode == 200 else {
        return .failure(
          AuthoritativeCostSupport.responseFailure(
            statusCode: response.statusCode,
            providerName: "OpenRouter",
            sourceName: "credits"))
      }
      let decoded = try JSONDecoder().decode(CreditsEnvelope.self, from: response.data).data
      let remaining = max(decoded.totalCredits.value - decoded.totalUsage.value, 0)
      return .success(
        AccountBalance(
          currency: "USD",
          available: remaining,
          purchased: decoded.totalCredits.value,
          used: decoded.totalUsage.value))
    } catch is DecodingError {
      return .failure(.decoding("OpenRouter credits could not be read."))
    } catch {
      return .failure(
        AuthoritativeCostSupport.transportFailure(
          error,
          providerName: "OpenRouter",
          sourceName: "credits"))
    }
  }

  private func fetchKey(key: String) async -> Result<KeySnapshot, ProviderFailure> {
    do {
      let response = try await http.data(
        for: AuthoritativeCostSupport.request(
          url: Self.keyURL,
          bearerToken: key),
        policy: Self.policy)
      guard response.statusCode == 200 else {
        return .failure(
          AuthoritativeCostSupport.responseFailure(
            statusCode: response.statusCode,
            providerName: "OpenRouter",
            sourceName: "key"))
      }
      let decoded = try JSONDecoder().decode(KeyEnvelope.self, from: response.data).data
      let snapshot = decoded.snapshot
      guard snapshot.balance != nil || !snapshot.periodSpend.isEmpty else {
        return .failure(.decoding("OpenRouter key usage was empty."))
      }
      return .success(snapshot)
    } catch is DecodingError {
      return .failure(.decoding("OpenRouter key usage could not be read."))
    } catch {
      return .failure(
        AuthoritativeCostSupport.transportFailure(
          error,
          providerName: "OpenRouter",
          sourceName: "key"))
    }
  }
}

private struct CreditsEnvelope: Decodable {
  let data: CreditsData
}

private struct CreditsData: Decodable {
  let totalCredits: LosslessDecimal
  let totalUsage: LosslessDecimal

  private enum CodingKeys: String, CodingKey {
    case totalCredits = "total_credits"
    case totalUsage = "total_usage"
  }
}

private struct KeyEnvelope: Decodable {
  let data: KeyData
}

private struct KeyData: Decodable {
  let limit: LosslessDecimal?
  let limitRemaining: LosslessDecimal?
  let usage: LosslessDecimal?
  let usageDaily: LosslessDecimal?
  let usageWeekly: LosslessDecimal?
  let usageMonthly: LosslessDecimal?

  private enum CodingKeys: String, CodingKey {
    case limit
    case limitRemaining = "limit_remaining"
    case usage
    case usageDaily = "usage_daily"
    case usageWeekly = "usage_weekly"
    case usageMonthly = "usage_monthly"
  }

  var snapshot: KeySnapshot {
    let balance = limitRemaining.map {
      AccountBalance(
        currency: "USD",
        available: $0.value,
        purchased: limit?.value,
        used: usage?.value)
    }
    let values: [(ProviderSpendPeriod, LosslessDecimal?)] = [
      (.daily, usageDaily),
      (.weekly, usageWeekly),
      (.monthly, usageMonthly),
      (.lifetime, usage),
    ]
    return KeySnapshot(
      balance: balance,
      periodSpend: values.compactMap { period, amount in
        amount.map {
          ProviderPeriodSpend(
            period: period,
            amount: CurrencyAmount(value: $0.value, currency: "USD"))
        }
      })
  }
}

private struct KeySnapshot: Sendable {
  let balance: AccountBalance?
  let periodSpend: [ProviderPeriodSpend]
}
