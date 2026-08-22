import Foundation
import TokenLinkCore

/// How the credential is placed into the `Authorization` header.
public enum ProviderAuthStyle: Sendable {
  /// `Authorization: Bearer <key>` (Kimi, MiniMax).
  case bearer
  /// `Authorization: <key>` without a scheme prefix (GLM).
  case rawAuthorization
}

/// Declarative description of a pure-HTTP quota provider. Providers that need
/// a local subprocess (Codex) are not spec-driven; see
/// `ProviderRegistry.customProviders`.
public struct ProviderSpec: Sendable {
  public let id: ProviderID
  public let displayName: String
  /// Resolves the quota endpoint for a region raw value (`nil` when the
  /// provider has no regions).
  public let endpoint: @Sendable (_ region: String?) -> URL
  /// Resolves the official console page where users obtain an API key.
  public let keyHelpURL: @Sendable (_ region: String?) -> URL
  public let authStyle: ProviderAuthStyle
  public let allowedHosts: [String]
  /// Explicit allowlist of environment variables consulted as a credential
  /// fallback, in priority order. Empty when the provider has none.
  public let credentialEnvVars: [String]
  /// Whether the provider may fall back to a local CLI credential (Kimi).
  public let allowsCLICredential: Bool
  public let missingCredentialMessage: String
  /// Parses a successful (HTTP 200) response body. The credential source on
  /// the returned snapshot is overridden by the resolved source.
  public let parse: @Sendable (Data, Date) throws -> QuotaSnapshot
  /// Maps provider-specific thrown errors to failures. Return `nil` to fall
  /// through to the default decoding/network mapping.
  public let errorMapper: @Sendable (Error) -> ProviderFailure?

  public init(
    id: ProviderID,
    displayName: String,
    endpoint: @escaping @Sendable (_ region: String?) -> URL,
    keyHelpURL: @escaping @Sendable (_ region: String?) -> URL,
    authStyle: ProviderAuthStyle,
    allowedHosts: [String],
    credentialEnvVars: [String],
    allowsCLICredential: Bool = false,
    missingCredentialMessage: String,
    parse: @escaping @Sendable (Data, Date) throws -> QuotaSnapshot,
    errorMapper: @escaping @Sendable (Error) -> ProviderFailure? = { _ in nil }
  ) {
    self.id = id
    self.displayName = displayName
    self.endpoint = endpoint
    self.keyHelpURL = keyHelpURL
    self.authStyle = authStyle
    self.allowedHosts = allowedHosts
    self.credentialEnvVars = credentialEnvVars
    self.allowsCLICredential = allowsCLICredential
    self.missingCredentialMessage = missingCredentialMessage
    self.parse = parse
    self.errorMapper = errorMapper
  }
}

public enum ProviderRegistry {
  public static let specs: [ProviderID: ProviderSpec] = [
    .kimi: kimi,
    .minimax: minimax,
    .glm: glm,
  ]

  /// Providers with a hand-written adapter (local subprocess, no API key).
  public static let customProviders: Set<ProviderID> = [.codex]

  public static func spec(for id: ProviderID) -> ProviderSpec? {
    specs[id]
  }

  public static func displayName(for id: ProviderID) -> String {
    if let spec = specs[id] { return spec.displayName }
    switch id {
    case .codex: return "Codex"
    default: return id.rawValue.capitalized
    }
  }

  public static let kimi = ProviderSpec(
    id: .kimi,
    displayName: "Kimi",
    endpoint: { _ in URL(string: "https://api.kimi.com/coding/v1/usages")! },
    keyHelpURL: { _ in URL(string: "https://www.kimi.com/code/console")! },
    authStyle: .bearer,
    allowedHosts: ["api.kimi.com"],
    credentialEnvVars: ["KIMI_CODE_API_KEY", "KIMI_API_KEY"],
    allowsCLICredential: true,
    missingCredentialMessage:
      "Configure a Kimi Coding API key or sign in with Kimi Code CLI.",
    parse: { data, fetchedAt in
      try KimiParser.parse(data: data, fetchedAt: fetchedAt, source: .apiKey)
    },
    errorMapper: { error in
      error is KimiParseError ? .decoding("Kimi usage could not be read.") : nil
    })

  public static let minimax = ProviderSpec(
    id: .minimax,
    displayName: "MiniMax",
    endpoint: { region in
      (region.flatMap(MiniMaxRegion.init(rawValue:)) ?? .global).endpoint
    },
    keyHelpURL: { region in
      switch region.flatMap(MiniMaxRegion.init(rawValue:)) ?? .global {
      case .global:
        return URL(string: "https://www.minimax.io")!
      case .china:
        return URL(
          string: "https://platform.minimaxi.com/user-center/basic-information/interface-key")!
      }
    },
    authStyle: .bearer,
    allowedHosts: ["www.minimax.io", "www.minimaxi.com"],
    credentialEnvVars: ["MINIMAX_API_KEY"],
    missingCredentialMessage: "Configure a MiniMax Coding Plan API key.",
    parse: { data, fetchedAt in
      try MiniMaxParser.parse(data: data, fetchedAt: fetchedAt)
    },
    errorMapper: { error in
      guard let parseError = error as? MiniMaxParseError else { return nil }
      switch parseError {
      case .service(let statusCode, let message):
        if MiniMaxParser.authenticationStatusCodes.contains(statusCode) {
          return .authentication("MiniMax: \(message)")
        }
        return .network("MiniMax: \(message)")
      case .missingModelRemains:
        return .decoding("MiniMax usage could not be read.")
      }
    })

  public static let glm = ProviderSpec(
    id: .glm,
    displayName: "GLM",
    endpoint: { region in
      (region.flatMap(GLMRegion.init(rawValue:)) ?? .global).endpoint
    },
    keyHelpURL: { region in
      switch region.flatMap(GLMRegion.init(rawValue:)) ?? .global {
      case .global:
        return URL(string: "https://z.ai")!
      case .china:
        return URL(string: "https://open.bigmodel.cn")!
      }
    },
    authStyle: .rawAuthorization,
    allowedHosts: ["api.z.ai", "open.bigmodel.cn"],
    credentialEnvVars: ["ZAI_API_KEY", "ZHIPU_API_KEY", "GLM_API_KEY", "BIGMODEL_API_KEY"],
    missingCredentialMessage: "Configure a GLM Coding Plan API key.",
    parse: { data, fetchedAt in
      try GLMParser.parse(data: data, fetchedAt: fetchedAt)
    },
    errorMapper: { error in
      error is GLMParseError ? .decoding("GLM usage could not be read.") : nil
    })
}
