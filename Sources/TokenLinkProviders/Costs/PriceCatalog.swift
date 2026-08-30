import Foundation
import TokenLinkCore

public enum PriceCatalogError: Error, Equatable, Sendable {
  case missingResource
  case invalidEffectiveDate
  case invalidEntry(String)
}

public struct PriceCatalog: Sendable {
  public let version: String
  public let effectiveDate: Date
  public let entries: [ModelPrice]

  private struct LookupKey: Hashable, Sendable {
    let provider: ProviderID
    let modelID: String
  }

  private let lookup: [LookupKey: ModelPrice]

  public init(version: String, effectiveDate: Date, entries: [ModelPrice]) {
    self.version = version
    self.effectiveDate = effectiveDate
    self.entries = entries
    var lookup: [LookupKey: ModelPrice] = [:]
    for entry in entries {
      lookup[LookupKey(provider: entry.provider, modelID: entry.modelID)] = entry
      for alias in entry.aliases {
        lookup[LookupKey(provider: entry.provider, modelID: alias)] = entry
      }
    }
    self.lookup = lookup
  }

  public func entry(provider: ProviderID, modelID: String) -> ModelPrice? {
    lookup[LookupKey(provider: provider, modelID: modelID)]
  }

  public static func bundled() throws -> PriceCatalog {
    guard
      let url = Bundle.module.url(
        forResource: "api-equivalent-prices",
        withExtension: "json")
    else { throw PriceCatalogError.missingResource }
    let document = try JSONDecoder().decode(
      CatalogDocument.self,
      from: Data(contentsOf: url))
    guard let effectiveDate = dayFormatter.date(from: document.effectiveDate) else {
      throw PriceCatalogError.invalidEffectiveDate
    }
    return PriceCatalog(
      version: document.version,
      effectiveDate: effectiveDate,
      entries: try document.entries.map(ModelPrice.init(document:)))
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}

private struct CatalogDocument: Decodable {
  let schemaVersion: Int
  let version: String
  let effectiveDate: String
  let entries: [PriceDocument]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case version
    case effectiveDate = "effective_date"
    case entries
  }
}

private struct PriceDocument: Decodable {
  let provider: ProviderID
  let modelID: String
  let aliases: [String]
  let currency: String
  let uncachedInputPerMillion: String?
  let cacheReadPerMillion: String?
  let cacheWriteFiveMinutePerMillion: String?
  let cacheWriteOneHourPerMillion: String?
  let outputPerMillion: String?
  let sourceURL: String
  let longContext: LongContextDocument?

  enum CodingKeys: String, CodingKey {
    case provider
    case modelID = "model_id"
    case aliases
    case currency
    case uncachedInputPerMillion = "uncached_input_per_million"
    case cacheReadPerMillion = "cache_read_per_million"
    case cacheWriteFiveMinutePerMillion = "cache_write_five_minute_per_million"
    case cacheWriteOneHourPerMillion = "cache_write_one_hour_per_million"
    case outputPerMillion = "output_per_million"
    case sourceURL = "source_url"
    case longContext = "long_context"
  }
}

private struct LongContextDocument: Decodable {
  let thresholdInputTokens: Int
  let inputMultiplier: String
  let outputMultiplier: String

  enum CodingKeys: String, CodingKey {
    case thresholdInputTokens = "threshold_input_tokens"
    case inputMultiplier = "input_multiplier"
    case outputMultiplier = "output_multiplier"
  }
}

extension ModelPrice {
  fileprivate init(document: PriceDocument) throws {
    guard let sourceURL = URL(string: document.sourceURL), sourceURL.scheme == "https" else {
      throw PriceCatalogError.invalidEntry(document.modelID)
    }
    let longContext: LongContextPricing?
    if let value = document.longContext {
      guard let inputMultiplier = Self.decimal(value.inputMultiplier),
        let outputMultiplier = Self.decimal(value.outputMultiplier)
      else { throw PriceCatalogError.invalidEntry(document.modelID) }
      longContext = LongContextPricing(
        thresholdInputTokens: value.thresholdInputTokens,
        inputMultiplier: inputMultiplier,
        outputMultiplier: outputMultiplier)
    } else {
      longContext = nil
    }
    self.init(
      provider: document.provider,
      modelID: document.modelID,
      aliases: document.aliases,
      currency: document.currency,
      uncachedInputPerMillion: try Self.decimal(
        document.uncachedInputPerMillion, modelID: document.modelID),
      cacheReadPerMillion: try Self.decimal(
        document.cacheReadPerMillion, modelID: document.modelID),
      cacheWriteFiveMinutePerMillion: try Self.decimal(
        document.cacheWriteFiveMinutePerMillion, modelID: document.modelID),
      cacheWriteOneHourPerMillion: try Self.decimal(
        document.cacheWriteOneHourPerMillion, modelID: document.modelID),
      outputPerMillion: try Self.decimal(
        document.outputPerMillion, modelID: document.modelID),
      sourceURL: sourceURL,
      longContext: longContext)
  }

  private static func decimal(_ value: String) -> Decimal? {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func decimal(_ value: String?, modelID: String) throws -> Decimal? {
    guard let value else { return nil }
    guard let parsed = decimal(value) else {
      throw PriceCatalogError.invalidEntry(modelID)
    }
    return parsed
  }
}
