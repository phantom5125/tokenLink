import Foundation
import Observation
import TokenLinkProviders

@MainActor
@Observable
public final class TokenizerFingerprintSession {
  public private(set) var isRunning = false
  public private(set) var completed = 0
  public private(set) var observations: [Int?] = []
  public private(set) var matches: [TokenizerFingerprintMatch] = []
  public private(set) var failure: Failure?
  public private(set) var probedTarget: String?
  public var prompts: [String] { catalog?.prompts ?? [] }
  public var referenceSummary: String {
    guard let catalog else { return "" }
    let dates = Set(catalog.profiles.map { String($0.sampledAt.prefix(10)) }).sorted()
    return "v\(catalog.version) · \(catalog.profiles.count) · \(dates.joined(separator: " / "))"
  }

  public enum Failure: Equatable {
    case catalog
    case missingKey
    case invalidModel
    case http(Int)
    case network
    case cancelled
  }

  @ObservationIgnored private let catalog: TokenizerFingerprintCatalog?
  @ObservationIgnored private let credentials: any CredentialReader
  @ObservationIgnored private let client: TokenizerProbeClient
  @ObservationIgnored private var task: Task<Void, Never>?

  public init(
    catalog: TokenizerFingerprintCatalog? = try? .bundled(),
    credentials: any CredentialReader,
    client: TokenizerProbeClient
  ) {
    self.catalog = catalog
    self.credentials = credentials
    self.client = client
  }

  /// No credential access or network work occurs until this explicit call.
  public func start(credentialAccount: String, target: TokenizerProbeTarget) {
    guard !isRunning else { return }
    isRunning = true
    completed = 0
    observations = []
    matches = []
    failure = nil
    probedTarget = "\(target.provider.rawValue) · \(target.model)"
    task = Task { await run(credentialAccount: credentialAccount, target: target) }
  }

  public func cancel() {
    task?.cancel()
  }

  private func run(credentialAccount: String, target: TokenizerProbeTarget) async {
    defer {
      isRunning = false
      task = nil
    }
    guard let catalog else {
      failure = .catalog
      return
    }
    do {
      guard let key = try await credentials.apiKey(forAccount: credentialAccount), !key.isEmpty
      else {
        failure = .missingKey
        return
      }
      for prompt in catalog.prompts {
        try Task.checkCancellation()
        let count = try await client.measure(target: target, apiKey: key, prompt: prompt)
        observations.append(count)
        completed += 1
      }
      matches = TokenizerFingerprintAnalysis.rank(observed: observations, catalog: catalog)
    } catch is CancellationError {
      failure = .cancelled
    } catch let error as TokenizerFingerprintError {
      switch error {
      case .invalidModel: failure = .invalidModel
      case .httpStatus(let status): failure = .http(status)
      case .catalogUnavailable: failure = .catalog
      default: failure = .network
      }
    } catch {
      failure = .network
    }
  }
}
