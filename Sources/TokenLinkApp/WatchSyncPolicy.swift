import Foundation
import TokenLinkCore
import TokenLinkDevice

/// Decides what the next payload to the watch is, given the negotiated
/// protocol, the per-provider snapshots the caller has already vetted, and the
/// watch settings. Pure function: no BLE, no state of its own.
public enum WatchSyncPolicy {
  public struct Decision: Equatable, Sendable {
    public let data: Data
    public let provider: ProviderID
    /// Pass this back as the next call's `rotationCursor`.
    public let nextCursor: Int
  }

  /// Builds the complete write batch for one connection. A v1 watch receives
  /// one Codex payload; a v2 watch receives one mergeable payload per
  /// candidate so its Quota page mirrors every selected menu-bar provider in
  /// the same refresh, instead of rotating sources over several minutes.
  public static func payloads(
    negotiated: NegotiatedProtocol,
    candidates: [(provider: ProviderID, snapshot: QuotaSnapshot)],
    settings: WatchSettings,
    workItems: [WorkItemPayload],
    activeSessionCount: Int? = nil,
    now: Date
  ) -> [Decision] {
    switch negotiated {
    case .v1:
      guard
        let codex = candidates.first(where: { $0.provider == .codex }),
        let data = try? LegacyWatchProjection.encode(snapshot: codex.snapshot, now: now)
      else { return [] }
      return [Decision(data: data, provider: .codex, nextCursor: 0)]

    case .v2:
      let state = WatchFaceState(
        snapshots: candidates.map(\.snapshot),
        workItems: workItems,
        activeSessionCount: activeSessionCount,
        capturedAt: now)
      let settingsPayload = WatchSettingsPayload(
        theme: settings.faceID.rawValue,
        wake: settings.wakeMode.rawValue,
        hourFormat: settings.hourFormat == .system
          ? "system" : settings.hourFormat.rawValue)
      return zip(candidates, state.providers).compactMap { candidate, provider in
        guard
          let data = try? WatchProjectionV2.encode(
            state: state,
            provider: provider,
            settings: settingsPayload)
        else { return nil }
        return Decision(data: data, provider: candidate.provider, nextCursor: 0)
      }
    }
  }

  /// - Parameters:
  ///   - negotiated: per-connection protocol from `DeviceBridge`.
  ///   - candidates: providers with an acceptable snapshot, already filtered
  ///     for freshness and sorted in `ProviderID.allCases` order. On v1 only
  ///     Codex may appear.
  ///   - rotationCursor: monotonically increasing counter so multi-provider
  ///     v2 syncs rotate through candidates instead of always sending one.
  public static func nextPayload(
    negotiated: NegotiatedProtocol,
    candidates: [(provider: ProviderID, snapshot: QuotaSnapshot)],
    settings: WatchSettings,
    workItems: [WorkItemPayload],
    activeSessionCount: Int? = nil,
    rotationCursor: Int,
    now: Date
  ) -> Decision? {
    switch negotiated {
    case .v1:
      guard let codex = candidates.first(where: { $0.provider == .codex }),
        let data = try? LegacyWatchProjection.encode(snapshot: codex.snapshot, now: now)
      else { return nil }
      return Decision(data: data, provider: .codex, nextCursor: rotationCursor)

    case .v2:
      guard !candidates.isEmpty else { return nil }
      let index = rotationCursor % candidates.count
      let chosen = candidates[index]
      let state = WatchFaceState(
        snapshots: candidates.map(\.snapshot),
        workItems: workItems,
        activeSessionCount: activeSessionCount,
        capturedAt: now)
      let settingsPayload = WatchSettingsPayload(
        theme: settings.faceID.rawValue,
        wake: settings.wakeMode.rawValue,
        hourFormat: settings.hourFormat == .system
          ? "system" : settings.hourFormat.rawValue)
      guard
        let data = try? WatchProjectionV2.encode(
          state: state,
          provider: state.providers[index],
          settings: settingsPayload)
      else { return nil }
      return Decision(
        data: data, provider: chosen.provider, nextCursor: rotationCursor + 1)
    }
  }
}
