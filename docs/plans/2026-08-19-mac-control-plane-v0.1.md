# TokenLink macOS Control Plane v0.1 Implementation Plan

**Goal:** Build a native macOS menu-bar control plane that displays Codex, Kimi, MiniMax, and GLM Coding Plan quota, stores explicit API keys in Keychain, and syncs the Codex primary window to the existing M5Stack StopWatch quota GATT protocol.

> Implementation status (2026-08-20): Tasks 1–12 and automated/package portions
> of Task 13 are complete. Real Codex validation passed. Interactive UI,
> credentialed Kimi/MiniMax/GLM requests, and physical StopWatch validation remain
> explicitly `NOT VERIFIED` in the validation report. The original step boxes
> below are retained as the pre-implementation procedure rather than rewritten as
> validation evidence.

**Architecture:** A Swift Package separates pure quota/state logic (`TokenLinkCore`), provider fetchers (`TokenLinkProviders`), CoreBluetooth transport (`TokenLinkDevice`), and the SwiftUI executable (`TokenLinkApp`). Provider adapters emit a shared `QuotaSnapshot`; the app shows every provider while `LegacyWatchProjection` sends only Codex to firmware protocol v1.

**Tech Stack:** Swift 6.2 language mode, SwiftUI, AppKit, Foundation, CoreBluetooth, Security, ServiceManagement, Swift Testing/XCTest, Swift Package Manager.

---

## Final file structure

```text
Package.swift
Sources/
  TokenLinkCore/
    ProviderModels.swift
    QuotaModels.swift
    ProviderState.swift
    RefreshCoordinator.swift
  TokenLinkProviders/
    Shared/ProviderSupport.swift
    Shared/URLSessionHTTPClient.swift
    Codex/CodexRateLimitParser.swift
    Codex/CodexAppServerClient.swift
    Codex/CodexProvider.swift
    Kimi/KimiCLICredentialReader.swift
    Kimi/KimiParser.swift
    Kimi/KimiProvider.swift
    MiniMax/MiniMaxParser.swift
    MiniMax/MiniMaxProvider.swift
    GLM/GLMParser.swift
    GLM/GLMProvider.swift
  TokenLinkDevice/
    DeviceModels.swift
    LegacyWatchProjection.swift
    CoreBluetoothDeviceBridge.swift
  TokenLinkApp/
    TokenLinkApp.swift
    AppModel.swift
    RefreshScheduler.swift
    ConfigurationStore.swift
    KeychainVault.swift
    LoginItemController.swift
    DiagnosticExporter.swift
    Views/MenuBarView.swift
    Views/ControlCenterView.swift
    Views/OverviewView.swift
    Views/ProvidersView.swift
    Views/StopWatchView.swift
    Views/SettingsView.swift
Tests/
  TokenLinkCoreTests/
  TokenLinkProviderTests/Fixtures/
  TokenLinkProviderTests/
  TokenLinkDeviceTests/
  TokenLinkAppTests/
packaging/Info.plist
scripts/package_app.sh
scripts/privacy_scan.sh
.github/workflows/ci.yml
README.md
NOTICE.md
SECURITY.md
CONTRIBUTING.md
```

## Task 1: Scaffold the Swift package and quota domain

**Files:**
- Create: `Package.swift`
- Create: `Sources/TokenLinkCore/ProviderModels.swift`
- Create: `Sources/TokenLinkCore/QuotaModels.swift`
- Create: `Tests/TokenLinkCoreTests/QuotaModelsTests.swift`

- [ ] **Step 1: Add the package manifest with only the first target**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TokenLink",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TokenLinkCore", targets: ["TokenLinkCore"])],
    targets: [
        .target(name: "TokenLinkCore"),
        .testTarget(name: "TokenLinkCoreTests", dependencies: ["TokenLinkCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write failing normalization and risk-order tests**

```swift
import Foundation
import Testing
@testable import TokenLinkCore

@Test func quotaWindowClampsPercentages() {
    let window = QuotaWindow(
        id: "weekly", label: "Weekly", usedPercent: 130,
        remainingPercent: -30, remainingCount: nil, limitCount: nil,
        resetsAt: nil)
    #expect(window.usedPercent == 100)
    #expect(window.remainingPercent == 0)
}

@Test func snapshotHighlightsLowestRemainingWindow() throws {
    let snapshot = QuotaSnapshot(
        provider: .kimi, planLabel: "Pro",
        windows: [
            .init(id: "weekly", label: "Weekly", usedPercent: 20,
                  remainingPercent: 80, remainingCount: nil, limitCount: nil, resetsAt: nil),
            .init(id: "5h", label: "5 hours", usedPercent: 75,
                  remainingPercent: 25, remainingCount: nil, limitCount: nil, resetsAt: nil),
        ],
        source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
    #expect(try #require(snapshot.mostConstrainedWindow).id == "5h")
}
```

- [ ] **Step 3: Run the test and verify the domain types are missing**

Run: `swift test --filter TokenLinkCoreTests`

Expected: FAIL because `QuotaWindow`, `QuotaSnapshot`, and related types do not exist.

- [ ] **Step 4: Implement the stable provider identifiers**

```swift
public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case codex
    case kimi
    case minimax
    case glm
}

public struct ProviderDescriptor: Equatable, Sendable {
    public let id: ProviderID
    public let displayName: String

    public init(id: ProviderID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
```

- [ ] **Step 5: Implement normalized quota values**

```swift
import Foundation

public enum CredentialSource: String, Codable, Sendable {
    case apiKey
    case cliCredential
    case localAppServer
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double?
    public let remainingPercent: Double
    public let remainingCount: Double?
    public let limitCount: Double?
    public let resetsAt: Date?

    public init(
        id: String, label: String, usedPercent: Double?, remainingPercent: Double,
        remainingCount: Double?, limitCount: Double?, resetsAt: Date?
    ) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.remainingCount = remainingCount
        self.limitCount = limitCount
        self.resetsAt = resetsAt
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let planLabel: String?
    public let windows: [QuotaWindow]
    public let source: CredentialSource
    public let fetchedAt: Date

    public var mostConstrainedWindow: QuotaWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    public init(
        provider: ProviderID, planLabel: String?, windows: [QuotaWindow],
        source: CredentialSource, fetchedAt: Date
    ) {
        self.provider = provider
        self.planLabel = planLabel
        self.windows = windows
        self.source = source
        self.fetchedAt = fetchedAt
    }
}
```

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter TokenLinkCoreTests`

Expected: PASS, 2 tests.

```bash
git add Package.swift Sources/TokenLinkCore Tests/TokenLinkCoreTests
git commit -m "feat: add normalized quota domain"
```

## Task 2: Add provider state and last-known-good refresh coordination

**Files:**
- Create: `Sources/TokenLinkCore/ProviderState.swift`
- Create: `Sources/TokenLinkCore/RefreshCoordinator.swift`
- Create: `Tests/TokenLinkCoreTests/RefreshCoordinatorTests.swift`

- [ ] **Step 1: Write failing state-transition tests**

```swift
import Foundation
import Testing
@testable import TokenLinkCore

private struct StubProvider: QuotaProvider {
    let id: ProviderID
    let result: Result<QuotaSnapshot, ProviderFailure>
    func fetch() async -> Result<QuotaSnapshot, ProviderFailure> { result }
}

@Test func failedRefreshKeepsLastKnownGoodAndMarksStale() async {
    let date = Date(timeIntervalSince1970: 100)
    let snapshot = QuotaSnapshot(
        provider: .kimi, planLabel: nil,
        windows: [.init(id: "5h", label: "5 hours", usedPercent: 40,
                        remainingPercent: 60, remainingCount: nil, limitCount: nil, resetsAt: nil)],
        source: .apiKey, fetchedAt: date)
    let store = ProviderStore(now: { Date(timeIntervalSince1970: 1_000) })
    await store.accept(.success(snapshot), provider: .kimi)
    await store.accept(.failure(.network("offline")), provider: .kimi)
    let state = await store.state(for: .kimi)
    #expect(state.snapshot == snapshot)
    #expect(state.phase == .stale)
    #expect(state.error?.kind == .network)
}

@Test func successfulSnapshotAgesFromHealthyToStale() async {
    let snapshot = QuotaSnapshot(provider: .glm, planLabel: nil,
        windows: [.init(id: "5h", label: "5 hours", usedPercent: 10,
                        remainingPercent: 90, remainingCount: nil, limitCount: nil, resetsAt: nil)],
        source: .apiKey, fetchedAt: Date(timeIntervalSince1970: 100))
    let store = ProviderStore(now: { Date(timeIntervalSince1970: 701) })
    await store.accept(.success(snapshot), provider: .glm)
    #expect(await store.state(for: .glm, refreshIntervalSeconds: 300).phase == .stale)
}
```

- [ ] **Step 2: Run the focused test**

Run: `swift test --filter RefreshCoordinatorTests`

Expected: FAIL because provider state and protocols do not exist.

- [ ] **Step 3: Implement provider failures and phases**

```swift
public enum ProviderErrorKind: String, Codable, Sendable {
    case missingCredential, authentication, network, decoding, process, timeout, configuration
}

public struct ProviderFailure: Error, Equatable, Sendable {
    public let kind: ProviderErrorKind
    public let message: String

    public init(kind: ProviderErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }

    public static func network(_ message: String) -> Self { .init(kind: .network, message: message) }
    public static func missingCredential(_ message: String) -> Self { .init(kind: .missingCredential, message: message) }
}

public enum ProviderPhase: String, Codable, Sendable {
    case disabled, missingCredential, refreshing, healthy, stale, error
}

public struct ProviderState: Equatable, Sendable {
    public var phase: ProviderPhase
    public var snapshot: QuotaSnapshot?
    public var error: ProviderFailure?

    public init(phase: ProviderPhase, snapshot: QuotaSnapshot? = nil, error: ProviderFailure? = nil) {
        self.phase = phase
        self.snapshot = snapshot
        self.error = error
    }
}
```

- [ ] **Step 4: Implement the provider protocol and actor store**

```swift
import Foundation

public protocol QuotaProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> Result<QuotaSnapshot, ProviderFailure>
}

public actor ProviderStore {
    private var states: [ProviderID: ProviderState] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) { self.now = now }

    public func accept(_ result: Result<QuotaSnapshot, ProviderFailure>, provider: ProviderID) {
        switch result {
        case .success(let snapshot):
            states[provider] = .init(phase: .healthy, snapshot: snapshot)
        case .failure(let failure):
            let old = states[provider]?.snapshot
            let phase: ProviderPhase = old == nil ?
                (failure.kind == .missingCredential ? .missingCredential : .error) : .stale
            states[provider] = .init(phase: phase, snapshot: old, error: failure)
        }
        _ = now()
    }

    public func markRefreshing(_ provider: ProviderID) {
        let old = states[provider]
        states[provider] = .init(phase: .refreshing, snapshot: old?.snapshot, error: nil)
    }

    public func state(for provider: ProviderID,
                      refreshIntervalSeconds: TimeInterval = 300) -> ProviderState {
        guard var state = states[provider] else { return .init(phase: .disabled) }
        guard state.phase == .healthy, let snapshot = state.snapshot else { return state }
        let age = now().timeIntervalSince(snapshot.fetchedAt)
        if age > 86_400 {
            state.phase = .error
            state.error = .init(kind: .timeout, message: "Cached quota is older than 24 hours.")
        } else if age > refreshIntervalSeconds * 2 {
            state.phase = .stale
        }
        return state
    }

    public func allStates() -> [ProviderID: ProviderState] { states }
}
```

- [ ] **Step 5: Add concurrent coordination**

```swift
public struct RefreshCoordinator: Sendable {
    private let providers: [any QuotaProvider]
    private let store: ProviderStore

    public init(providers: [any QuotaProvider], store: ProviderStore) {
        self.providers = providers
        self.store = store
    }

    public func refreshAll() async {
        await withTaskGroup(of: (ProviderID, Result<QuotaSnapshot, ProviderFailure>).self) { group in
            for provider in providers {
                await store.markRefreshing(provider.id)
                group.addTask { (provider.id, await provider.fetch()) }
            }
            for await (id, result) in group { await store.accept(result, provider: id) }
        }
    }
}
```

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter TokenLinkCoreTests`

Expected: PASS.

```bash
git add Sources/TokenLinkCore Tests/TokenLinkCoreTests
git commit -m "feat: coordinate provider refresh state"
```

## Task 3: Create the secure provider host interfaces

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TokenLinkProviders/Shared/ProviderSupport.swift`
- Create: `Sources/TokenLinkProviders/Shared/URLSessionHTTPClient.swift`
- Create: `Tests/TokenLinkProviderTests/ProviderSupportTests.swift`

- [ ] **Step 1: Add provider target and test target to `Package.swift`**

Add the product and targets:

```swift
.library(name: "TokenLinkProviders", targets: ["TokenLinkProviders"])
```

```swift
.target(name: "TokenLinkProviders", dependencies: ["TokenLinkCore"]),
.testTarget(name: "TokenLinkProviderTests", dependencies: ["TokenLinkCore", "TokenLinkProviders"]),
```

- [ ] **Step 2: Write failing endpoint-policy tests**

```swift
import Foundation
import Testing
@testable import TokenLinkProviders

@Test func endpointPolicyRejectsPlainHTTPAndUnknownHosts() throws {
    let policy = EndpointPolicy(allowedHosts: ["api.kimi.com"])
    #expect(throws: ProviderHostError.self) {
        try policy.validate(URL(string: "http://api.kimi.com/coding/v1/usages")!)
    }
    #expect(throws: ProviderHostError.self) {
        try policy.validate(URL(string: "https://example.com/coding/v1/usages")!)
    }
    #expect(try policy.validate(URL(string: "https://api.kimi.com/coding/v1/usages")!).host == "api.kimi.com")
}
```

- [ ] **Step 3: Run the focused test**

Run: `swift test --filter ProviderSupportTests`

Expected: FAIL because `EndpointPolicy` does not exist.

- [ ] **Step 4: Implement narrow host APIs**

```swift
import Foundation
import TokenLinkCore

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
}

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse
}

public protocol CredentialReader: Sendable {
    func apiKey(for provider: ProviderID) async throws -> String?
    func cliAccessToken(for provider: ProviderID) async throws -> String?
}

public struct ProviderHostError: Error, Equatable {}

public struct EndpointPolicy: Sendable {
    public let allowedHosts: Set<String>
    public init(allowedHosts: Set<String>) { self.allowedHosts = allowedHosts }
    public init(allowedHosts: [String]) { self.allowedHosts = Set(allowedHosts) }

    public func validate(_ url: URL) throws -> URL {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), allowedHosts.contains(host)
        else { throw ProviderHostError() }
        return url
    }
}
```

- [ ] **Step 5: Implement URLSession with validation before credential-bearing requests**

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest, policy: EndpointPolicy) async throws -> HTTPResponse {
        guard let url = request.url else { throw ProviderHostError() }
        _ = try policy.validate(url)
        var boundedRequest = request
        boundedRequest.timeoutInterval = 20
        let (data, response) = try await session.data(for: boundedRequest)
        guard let http = response as? HTTPURLResponse else { throw ProviderHostError() }
        return HTTPResponse(data: data, statusCode: http.statusCode)
    }
}
```

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter TokenLinkProviderTests`

Expected: PASS.

```bash
git add Package.swift Sources/TokenLinkProviders Tests/TokenLinkProviderTests
git commit -m "feat: add secure provider host interfaces"
```

## Task 4: Implement the Kimi Coding Plan adapter

**Files:**
- Create: `Sources/TokenLinkProviders/Kimi/KimiParser.swift`
- Create: `Sources/TokenLinkProviders/Kimi/KimiProvider.swift`
- Create: `Sources/TokenLinkProviders/Kimi/KimiCLICredentialReader.swift`
- Create: `Tests/TokenLinkProviderTests/Fixtures/kimi-usages.json`
- Create: `Tests/TokenLinkProviderTests/KimiProviderTests.swift`

- [ ] **Step 1: Add a synthetic Kimi fixture**

```json
{
  "subType": "BASIC",
  "usage": {"limit": "2048", "used": "512", "remaining": "1536", "resetTime": "2026-08-24T00:00:00Z"},
  "limits": [{"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"}, "detail": {"limit": "200", "used": "80", "remaining": "120", "resetTime": "2026-08-19T15:00:00Z"}}
}
```

- [ ] **Step 2: Write a failing parser test**

```swift
import Foundation
import Testing
@testable import TokenLinkProviders

@Test func parsesKimiWeeklyAndFiveHourWindows() throws {
    let data = try Fixture.load("kimi-usages.json")
    let snapshot = try KimiParser.parse(data: data, fetchedAt: Date(timeIntervalSince1970: 1_787_130_000), source: .apiKey)
    #expect(snapshot.provider == .kimi)
    #expect(snapshot.planLabel == "BASIC")
    #expect(snapshot.windows.map(\.id) == ["weekly", "5h"])
    #expect(snapshot.windows[0].remainingPercent == 75)
    #expect(snapshot.windows[1].remainingPercent == 60)
}
```

Also create the fixture loader in `Tests/TokenLinkProviderTests/Fixture.swift`:

```swift
import Foundation

enum Fixture {
    static func load(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil)!
        return try Data(contentsOf: url)
    }
}
```

Configure the test target with `.process("Fixtures")` resources.

- [ ] **Step 3: Run the focused test**

Run: `swift test --filter KimiProviderTests`

Expected: FAIL because `KimiParser` does not exist.

- [ ] **Step 4: Implement deterministic Kimi parsing**

Implement `KimiParser` with private `Decodable` response structs, `ISO8601DateFormatter`, string-or-number decoding, and this mapping:

```swift
public enum KimiParser {
    public static func parse(data: Data, fetchedAt: Date, source: CredentialSource) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
        let weekly = try response.usage.quotaWindow(id: "weekly", label: "Weekly")
        let rolling = try response.limits.compactMap { limit -> QuotaWindow? in
            guard limit.window.duration == 300 else { return nil }
            return try limit.detail?.quotaWindow(id: "5h", label: "5 hours") ??
                QuotaWindow(id: "5h", label: "5 hours", usedPercent: 0,
                            remainingPercent: 100, remainingCount: nil, limitCount: nil, resetsAt: nil)
        }
        return QuotaSnapshot(provider: .kimi, planLabel: response.subType,
                             windows: [weekly] + rolling, source: source, fetchedAt: fetchedAt)
    }
}
```

- [ ] **Step 5: Implement API-key-first fetching**

```swift
public struct KimiProvider: QuotaProvider {
    public let id: ProviderID = .kimi
    private let http: any HTTPClient
    private let credentials: any CredentialReader
    private let now: @Sendable () -> Date

    public init(http: any HTTPClient, credentials: any CredentialReader,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.http = http; self.credentials = credentials; self.now = now
    }

    public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
        do {
            let explicit = try await credentials.apiKey(for: .kimi)
            let token = explicit ?? (try await credentials.cliAccessToken(for: .kimi))
            guard let token, !token.isEmpty else {
                return .failure(.missingCredential("Configure a Kimi Coding API key or sign in with Kimi Code CLI."))
            }
            var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let response = try await http.data(for: request, policy: .init(allowedHosts: ["api.kimi.com"]))
            guard response.statusCode == 200 else {
                return .failure(.init(kind: response.statusCode == 401 ? .authentication : .network,
                                      message: "Kimi returned HTTP \(response.statusCode)."))
            }
            return .success(try KimiParser.parse(data: response.data, fetchedAt: now(),
                                                 source: explicit == nil ? .cliCredential : .apiKey))
        } catch {
            return .failure(.init(kind: .decoding, message: "Kimi usage could not be read."))
        }
    }
}
```

`KimiCLICredentialReader` receives an explicit home URL, reads only
`<home>/.kimi-code/credentials/kimi-code.json`, decodes `access_token` and its
expiry, and returns `nil` for expired credentials. It never returns or writes
`refresh_token`. Add tests with a temporary home directory proving that no
sibling file or alternate browser path is inspected.

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter KimiProviderTests`

Expected: PASS.

```bash
git add Package.swift Sources/TokenLinkProviders/Kimi Tests/TokenLinkProviderTests
git commit -m "feat: support Kimi coding quota"
```

## Task 5: Implement MiniMax Coding Plan parsing and fetching

**Files:**
- Create: `Sources/TokenLinkProviders/MiniMax/MiniMaxParser.swift`
- Create: `Sources/TokenLinkProviders/MiniMax/MiniMaxProvider.swift`
- Create: `Tests/TokenLinkProviderTests/Fixtures/minimax-remains.json`
- Create: `Tests/TokenLinkProviderTests/MiniMaxProviderTests.swift`

- [ ] **Step 1: Add the verified response-shape fixture**

```json
{
  "model_remains": [
    {"model_name": "MiniMax-M2.5", "current_interval_remaining_percent": 60, "current_weekly_remaining_percent": 92, "current_interval_reset_time": 1787137200000, "current_weekly_reset_time": 1787616000000}
  ],
  "base_resp": {"status_code": 0, "status_msg": "success"}
}
```

- [ ] **Step 2: Write failing tests for percentages and error envelope**

```swift
@Test func parsesMiniMaxFiveHourAndWeeklyWindows() throws {
    let snapshot = try MiniMaxParser.parse(
        data: Fixture.load("minimax-remains.json"),
        fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
    #expect(snapshot.provider == .minimax)
    #expect(snapshot.windows.map(\.remainingPercent) == [60, 92])
}

@Test func rejectsMiniMaxErrorEnvelope() {
    let data = Data(#"{"base_resp":{"status_code":1004,"status_msg":"invalid key"}}"#.utf8)
    #expect(throws: MiniMaxParseError.self) {
        try MiniMaxParser.parse(data: data, fetchedAt: .distantPast)
    }
}
```

- [ ] **Step 3: Run, implement, and re-run**

Run: `swift test --filter MiniMaxProviderTests`

Expected before implementation: FAIL. Implement explicit `Decodable` structs that require `base_resp.status_code == 0`, select the first `model_remains` row, convert millisecond reset timestamps, and emit `5h` then `weekly` windows.

Expected after implementation: PASS.

- [ ] **Step 4: Implement region-bound requests**

```swift
public enum MiniMaxRegion: String, Codable, Sendable { case global, china }

public struct MiniMaxProvider: QuotaProvider {
    public let id: ProviderID = .minimax
    let region: MiniMaxRegion
    let http: any HTTPClient
    let credentials: any CredentialReader
    let now: @Sendable () -> Date

    var endpoint: URL {
        switch region {
        case .global: URL(string: "https://www.minimax.io/v1/token_plan/remains")!
        case .china: URL(string: "https://platform.minimaxi.com/v1/token_plan/remains")!
        }
    }

    public func fetch() async -> Result<QuotaSnapshot, ProviderFailure> {
        do {
            guard let key = try await credentials.apiKey(for: .minimax), !key.isEmpty else {
                return .failure(.missingCredential("Configure a MiniMax Coding Plan API key."))
            }
            var request = URLRequest(url: endpoint)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let policy = EndpointPolicy(allowedHosts: ["www.minimax.io", "platform.minimaxi.com"])
            let response = try await http.data(for: request, policy: policy)
            guard response.statusCode == 200 else {
                return .failure(.init(kind: response.statusCode == 401 ? .authentication : .network,
                                      message: "MiniMax returned HTTP \(response.statusCode)."))
            }
            return .success(try MiniMaxParser.parse(data: response.data, fetchedAt: now()))
        } catch {
            return .failure(.init(kind: .decoding, message: "MiniMax usage could not be read."))
        }
    }
}
```

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter MiniMaxProviderTests`

```bash
git add Sources/TokenLinkProviders/MiniMax Tests/TokenLinkProviderTests
git commit -m "feat: support MiniMax coding quota"
```

## Task 6: Implement GLM Coding Plan parsing and regions

**Files:**
- Create: `Sources/TokenLinkProviders/GLM/GLMParser.swift`
- Create: `Sources/TokenLinkProviders/GLM/GLMProvider.swift`
- Create: `Tests/TokenLinkProviderTests/Fixtures/glm-quota.json`
- Create: `Tests/TokenLinkProviderTests/GLMProviderTests.swift`

- [ ] **Step 1: Add a synthetic official-shape fixture**

```json
{
  "code": 200,
  "data": {
    "limits": [
      {"type": "TOKENS_LIMIT", "unit": "5h", "used_percent": 7, "remaining_percent": 93, "reset_time": 1787137200000},
      {"type": "TOKENS_LIMIT", "unit": "weekly", "used_percent": 18, "remaining_percent": 82, "reset_time": 1787616000000}
    ]
  }
}
```

- [ ] **Step 2: Write the failing parser test**

```swift
@Test func parsesGLMWindowsWithoutInferringPlanLimits() throws {
    let snapshot = try GLMParser.parse(data: Fixture.load("glm-quota.json"),
                                       fetchedAt: Date(timeIntervalSince1970: 1_787_130_000))
    #expect(snapshot.provider == .glm)
    #expect(snapshot.windows.map(\.id) == ["5h", "weekly"])
    #expect(snapshot.windows.map(\.remainingPercent) == [93, 82])
    #expect(snapshot.windows.allSatisfy { $0.limitCount == nil })
}
```

- [ ] **Step 3: Implement explicit response decoding and region selection**

Implement `GLMParser` using `Decodable` structs for `code`, `data.limits`, and millisecond reset timestamps. Implement:

```swift
public enum GLMRegion: String, Codable, Sendable { case global, china }

extension GLMRegion {
    var endpoint: URL {
        switch self {
        case .global: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
        case .china: URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
        }
    }
}
```

`GLMProvider.fetch()` must use only `api.z.ai` or `open.bigmodel.cn`, set `Authorization` to the Keychain API key, map 401/403 to `.authentication`, and parse all returned windows without plan-based estimates.

- [ ] **Step 4: Verify and commit**

Run: `swift test --filter GLMProviderTests`

Expected: PASS.

```bash
git add Sources/TokenLinkProviders/GLM Tests/TokenLinkProviderTests
git commit -m "feat: support GLM coding quota"
```

## Task 7: Implement Codex App Server quota access

**Files:**
- Create: `Sources/TokenLinkProviders/Codex/CodexRateLimitParser.swift`
- Create: `Sources/TokenLinkProviders/Codex/CodexAppServerClient.swift`
- Create: `Sources/TokenLinkProviders/Codex/CodexProvider.swift`
- Create: `Tests/TokenLinkProviderTests/Fixtures/codex-rate-limits.json`
- Create: `Tests/TokenLinkProviderTests/CodexProviderTests.swift`

- [ ] **Step 1: Add primary and legacy response fixtures**

Primary fixture:

```json
{"id":1,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":18,"resetsAt":1787616000}}}}}
```

Legacy fixture in the test body:

```json
{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":32,"resetsAt":1787616000}}}}
```

- [ ] **Step 2: Write failing parser tests**

```swift
@Test func parsesCurrentAndLegacyCodexRateLimits() throws {
    let now = Date(timeIntervalSince1970: 1_787_130_000)
    let current = try CodexRateLimitParser.parse(data: Fixture.load("codex-rate-limits.json"), fetchedAt: now)
    #expect(current.windows[0].remainingPercent == 82)
    let legacyData = Data(#"{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":32,"resetsAt":1787616000}}}}"#.utf8)
    let legacy = try CodexRateLimitParser.parse(data: legacyData, fetchedAt: now)
    #expect(legacy.windows[0].remainingPercent == 68)
}
```

- [ ] **Step 3: Implement the parser and JSONL transport boundary**

Define:

```swift
public protocol AppServerTransport: Sendable {
    func start(executable: URL) async throws
    func send(_ message: AppServerMessage) async throws
    func response(id: Int, timeout: Duration) async throws -> Data
    func stop() async
}

public enum AppServerMessage: Equatable, Sendable {
    case initialize
    case initialized
    case rateLimits(id: Int)
}
```

`CodexRateLimitParser` must accept current and legacy shapes, require a numeric `usedPercent` and Unix-second `resetsAt`, then emit a single `primary` window with `remainingPercent = 100 - usedPercent`.

- [ ] **Step 4: Implement `ProcessAppServerTransport`**

Use `Process`, stdin/stdout `Pipe`, an actor-owned newline buffer, request IDs, a 2,000-character stderr tail, and cancellation-safe termination. Launch arguments must be exactly:

```swift
process.arguments = ["app-server", "--listen", "stdio://"]
```

`ProcessAppServerTransport` encodes the message enum to these exact JSON-RPC
objects before appending one newline:

```swift
["method": "initialize", "id": 0,
 "params": ["clientInfo": ["name": "tokenlink", "title": "TokenLink", "version": "0.1.0"]]]
["method": "initialized", "params": [:]]
```

The quota request is:

```swift
["method": "account/rateLimits/read", "id": 1, "params": [:]]
```

- [ ] **Step 5: Add fake-transport timeout and shutdown tests**

Create an actor `FakeAppServerTransport` that records sent methods and returns fixture data. Verify `CodexProvider.fetch()` sends initialize before quota, maps timeout to `.timeout`, and always calls `stop()`.

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter CodexProviderTests`

Expected: PASS.

```bash
git add Sources/TokenLinkProviders/Codex Tests/TokenLinkProviderTests
git commit -m "feat: read Codex quota from app server"
```

## Task 8: Project Codex quota into the existing watch payload

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TokenLinkDevice/DeviceModels.swift`
- Create: `Sources/TokenLinkDevice/LegacyWatchProjection.swift`
- Create: `Tests/TokenLinkDeviceTests/LegacyWatchProjectionTests.swift`

- [ ] **Step 1: Add `TokenLinkDevice` targets**

```swift
.library(name: "TokenLinkDevice", targets: ["TokenLinkDevice"])
```

```swift
.target(name: "TokenLinkDevice", dependencies: ["TokenLinkCore"]),
.testTarget(name: "TokenLinkDeviceTests", dependencies: ["TokenLinkCore", "TokenLinkDevice"]),
```

- [ ] **Step 2: Write failing compatibility tests**

```swift
import Foundation
import Testing
@testable import TokenLinkCore
@testable import TokenLinkDevice

@Test func legacyProjectionEncodesExactV1Keys() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = QuotaSnapshot(
        provider: .codex, planLabel: nil,
        windows: [.init(id: "primary", label: "Primary", usedPercent: 28,
                        remainingPercent: 72, remainingCount: nil, limitCount: nil,
                        resetsAt: Date(timeIntervalSince1970: 1_900))],
        source: .localAppServer, fetchedAt: now)
    let data = try LegacyWatchProjection.encode(snapshot: snapshot, now: now)
    let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(object.keys.sorted() == ["remaining_percent", "reset_in_seconds"])
    #expect(object["remaining_percent"] as? Double == 72)
    #expect(object["reset_in_seconds"] as? Int == 900)
}

@Test func legacyProjectionRejectsNonCodexSnapshots() {
    #expect(throws: WatchProjectionError.self) {
        try LegacyWatchProjection.encode(snapshot: .init(provider: .kimi, planLabel: nil,
            windows: [], source: .apiKey, fetchedAt: .distantPast), now: .now)
    }
}
```

- [ ] **Step 3: Implement version-one encoding**

```swift
import Foundation
import TokenLinkCore

public enum WatchProjectionError: Error { case notCodex, missingPrimary, payloadTooLarge }

private struct LegacyQuotaPayload: Encodable {
    let remainingPercent: Double
    let resetInSeconds: Int
    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case resetInSeconds = "reset_in_seconds"
    }
}

public enum LegacyWatchProjection {
    public static func encode(snapshot: QuotaSnapshot, now: Date) throws -> Data {
        guard snapshot.provider == .codex else { throw WatchProjectionError.notCodex }
        guard let window = snapshot.windows.first(where: { $0.id == "primary" }) else {
            throw WatchProjectionError.missingPrimary
        }
        let seconds = max(0, Int((window.resetsAt ?? now).timeIntervalSince(now)))
        let data = try JSONEncoder().encode(LegacyQuotaPayload(
            remainingPercent: window.remainingPercent, resetInSeconds: seconds))
        guard data.count <= 512 else { throw WatchProjectionError.payloadTooLarge }
        return data
    }
}
```

- [ ] **Step 4: Verify and commit**

Run: `swift test --filter TokenLinkDeviceTests`

Expected: PASS.

```bash
git add Package.swift Sources/TokenLinkDevice Tests/TokenLinkDeviceTests
git commit -m "feat: encode legacy watch quota payload"
```

## Task 9: Add the CoreBluetooth device state machine

**Files:**
- Modify: `Sources/TokenLinkDevice/DeviceModels.swift`
- Create: `Sources/TokenLinkDevice/CoreBluetoothDeviceBridge.swift`
- Create: `Tests/TokenLinkDeviceTests/DeviceBridgeStateTests.swift`

- [ ] **Step 1: Write failing binding and retry tests against a transport protocol**

Define test doubles and verify:

```swift
@Test func bridgeIgnoresUnboundPeripheralAndWritesBoundOne() async throws {
    let bound = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let transport = FakeBLETransport(discovered: [other, bound])
    let bridge = DeviceBridge(transport: transport, boundIdentifier: bound)
    try await bridge.connect()
    #expect(await transport.connectedIdentifiers == [bound])
}
```

- [ ] **Step 2: Implement transport-independent device coordination**

```swift
public enum DevicePhase: Equatable, Sendable {
    case unbound, disconnected, scanning, connecting, connected, syncing, synced(Date), stale
}

public protocol BLETransport: Sendable {
    func discoveredIdentifiers() async throws -> [UUID]
    func connect(identifier: UUID) async throws
    func writeWithResponse(_ data: Data) async throws
    func disconnect() async
}

public actor DeviceBridge {
    private let transport: any BLETransport
    private let boundIdentifier: UUID?
    public private(set) var phase: DevicePhase

    public init(transport: any BLETransport, boundIdentifier: UUID?) {
        self.transport = transport; self.boundIdentifier = boundIdentifier
        self.phase = boundIdentifier == nil ? .unbound : .disconnected
    }

    public func connect() async throws {
        guard let boundIdentifier else { return }
        phase = .scanning
        guard try await transport.discoveredIdentifiers().contains(boundIdentifier) else {
            phase = .disconnected; return
        }
        phase = .connecting
        try await transport.connect(identifier: boundIdentifier)
        phase = .connected
    }

    public func sync(_ data: Data, now: Date = .now) async throws {
        phase = .syncing
        try await transport.writeWithResponse(data)
        phase = .synced(now)
    }
}
```

- [ ] **Step 3: Implement `CoreBluetoothTransport`**

Use the existing protocol constants exactly:

```swift
public static let quotaServiceUUID = CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01")
public static let quotaWriteUUID = CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02")
```

`CBCentralManagerDelegate` and `CBPeripheralDelegate` callbacks must resume checked continuations exactly once, filter writes to the bound CoreBluetooth UUID, discover only the private service/characteristic after connection, and use `.withResponse`.

- [ ] **Step 4: Verify and commit**

Run: `swift test --filter TokenLinkDeviceTests`

Expected: PASS without requiring Bluetooth hardware.

```bash
git add Sources/TokenLinkDevice Tests/TokenLinkDeviceTests
git commit -m "feat: manage bound StopWatch connection"
```

## Task 10: Add configuration and Keychain storage

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TokenLinkApp/ConfigurationStore.swift`
- Create: `Sources/TokenLinkApp/KeychainVault.swift`
- Create: `Sources/TokenLinkApp/LoginItemController.swift`
- Create: `Tests/TokenLinkAppTests/ConfigurationStoreTests.swift`
- Create: `Tests/TokenLinkAppTests/KeychainVaultTests.swift`

- [ ] **Step 1: Add the app executable and app test targets**

```swift
.executable(name: "tokenlink", targets: ["TokenLinkApp"])
```

```swift
.executableTarget(name: "TokenLinkApp",
                  dependencies: ["TokenLinkCore", "TokenLinkProviders", "TokenLinkDevice"]),
.testTarget(name: "TokenLinkAppTests",
            dependencies: ["TokenLinkApp", "TokenLinkCore", "TokenLinkProviders", "TokenLinkDevice"]),
```

- [ ] **Step 2: Write atomic configuration round-trip tests**

```swift
@Test func configurationRoundTripsWithoutSecrets() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = ConfigurationStore(directory: directory)
    let expected = AppConfiguration(enabledProviders: [.codex, .kimi], refreshMinutes: 5,
                                    boundDeviceIdentifier: nil, codexPath: nil,
                                    miniMaxRegion: .global, glmRegion: .china)
    try store.save(expected)
    #expect(try store.load() == expected)
    let bytes = try Data(contentsOf: directory.appending(path: "config.json"))
    #expect(!String(decoding: bytes, as: UTF8.self).localizedCaseInsensitiveContains("apiKey"))
}
```

- [ ] **Step 3: Implement app configuration with atomic replacement**

`AppConfiguration` is `Codable`, `Equatable`, and contains only the fields in the test. `ConfigurationStore.save` creates the directory with user-only permissions, encodes to `config.json.tmp`, then uses `replaceItemAt` or `moveItem` for first write. A decode failure moves the corrupt file to `config.json.invalid-<timestamp>` and returns defaults.

- [ ] **Step 4: Implement Keychain storage under the approved namespace**

```swift
import Security
import TokenLinkCore
import TokenLinkProviders

public struct KeychainVault: CredentialReader, Sendable {
    static let service = "io.github.phantom5125.tokenlink.provider"

    public func apiKey(for provider: ProviderID) async throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeAll()
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw ProviderFailure(kind: .configuration, message: "Keychain access failed.")
        }
        return value
    }

    public func cliAccessToken(for provider: ProviderID) async throws -> String? {
        guard provider == .kimi else { return nil }
        return try KimiCLICredentialReader().currentAccessToken()
    }
}
```

Add `setAPIKey(_:for:)` using `SecItemUpdate` with `SecItemAdd` fallback and `deleteAPIKey(for:)` using `SecItemDelete`. Tests call an injected `KeychainClient` fake rather than the real login Keychain.

- [ ] **Step 5: Add login-item control**

Use `SMAppService.mainApp.register()` and `.unregister()` behind a small `LoginItemControlling` protocol. Report `.requiresApproval` as a user-visible state rather than claiming success.

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter TokenLinkAppTests`

Expected: PASS and no real Keychain entries created by tests.

```bash
git add Package.swift Sources/TokenLinkApp Tests/TokenLinkAppTests
git commit -m "feat: persist settings and provider secrets"
```

## Task 11: Build `AppModel`, menu bar, and control-center UI

**Files:**
- Create: `Sources/TokenLinkApp/AppModel.swift`
- Create: `Sources/TokenLinkApp/RefreshScheduler.swift`
- Create: `Sources/TokenLinkApp/DiagnosticExporter.swift`
- Create: `Sources/TokenLinkApp/TokenLinkApp.swift`
- Create: `Sources/TokenLinkApp/Views/MenuBarView.swift`
- Create: `Sources/TokenLinkApp/Views/ControlCenterView.swift`
- Create: `Sources/TokenLinkApp/Views/OverviewView.swift`
- Create: `Sources/TokenLinkApp/Views/ProvidersView.swift`
- Create: `Sources/TokenLinkApp/Views/StopWatchView.swift`
- Create: `Sources/TokenLinkApp/Views/SettingsView.swift`
- Create: `Tests/TokenLinkAppTests/AppModelTests.swift`

- [ ] **Step 1: Write failing view-model behavior tests**

```swift
private actor CountingRefresher: AppRefreshing {
    private(set) var count = 0
    func refresh() async { count += 1 }
}

private final class TestNow: @unchecked Sendable {
    let value: Date
    init(_ value: Date) { self.value = value }
    func callAsFunction() -> Date { value }
}

private func snapshot(_ provider: ProviderID, remaining: Double) -> QuotaSnapshot {
    QuotaSnapshot(provider: provider, planLabel: nil,
        windows: [.init(id: "primary", label: "Primary", usedPercent: 100 - remaining,
                        remainingPercent: remaining, remainingCount: nil,
                        limitCount: nil, resetsAt: nil)],
        source: provider == .codex ? .localAppServer : .apiKey,
        fetchedAt: Date(timeIntervalSince1970: 100))
}

@MainActor @Test func appModelHighlightsLowestHealthyWindow() async {
    let model = AppModel.preview(snapshots: [snapshot(.codex, remaining: 72),
                                             snapshot(.kimi, remaining: 24)])
    #expect(model.highlight?.provider == .kimi)
    #expect(model.highlight?.window.remainingPercent == 24)
}

@MainActor @Test func manualRefreshIsThrottledForTenSeconds() async {
    let clock = TestNow(Date(timeIntervalSince1970: 100))
    let refresher = CountingRefresher()
    let model = AppModel(refresher: refresher, now: clock.callAsFunction)
    await model.refreshManually()
    await model.refreshManually()
    #expect(await refresher.count == 1)
}

@Test func schedulerUsesConfiguredFiveMinuteInterval() {
    let scheduler = RefreshScheduler(minutes: 5)
    #expect(scheduler.interval == .seconds(300))
}
```

- [ ] **Step 2: Implement `AppModel` as the only UI state owner**

`AppModel` is `@MainActor @Observable`. It exposes ordered provider rows, device phase, last events, `highlight`, `refreshManually()`, `saveAPIKey`, `bindDevice`, and `syncCodexNow`. It obtains snapshots through `RefreshCoordinator`, then encodes only the healthy/stale-acceptable Codex primary snapshot through `LegacyWatchProjection`.

Define `AppRefreshing: Sendable` with `func refresh() async`, conform
`RefreshCoordinator` by forwarding to `refreshAll()`, and inject that protocol
plus the `now` closure into `AppModel`. `AppModel.preview(snapshots:)` builds a
non-networked model used by tests and SwiftUI previews.

`RefreshScheduler` owns the cancellable periodic task and supports only 1, 2,
5, 15, or 30 minutes. `AppModel.start()` performs an immediate refresh, starts
the scheduler, observes `NSWorkspace.didWakeNotification`, and uses
`NWPathMonitor` to request one jittered refresh when connectivity returns. The
same actor coalesces simultaneous wake/network/manual triggers.

- [ ] **Step 3: Add the app entry point**

```swift
import SwiftUI

@main
struct TokenLinkApplication: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label(model.menuBarLabel, systemImage: "gauge.with.dots.needle.33percent")
        }
        .menuBarExtraStyle(.window)

        Window("TokenLink", id: "control-center") {
            ControlCenterView(model: model)
                .frame(minWidth: 860, minHeight: 590)
        }
        .defaultSize(width: 980, height: 680)
    }
}
```

- [ ] **Step 4: Implement the menu-bar hierarchy**

`MenuBarView` renders device status, one `ProviderQuotaRow` per enabled provider, a `ProgressView(value: remainingPercent, total: 100)`, reset text, Refresh, and an `OpenWindowAction` for `control-center`. Stale rows display the original `fetchedAt` and never use a green live indicator.

- [ ] **Step 5: Implement the four control-center routes**

`ControlCenterView` uses `NavigationSplitView` with exactly:

```swift
enum ControlRoute: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case providers = "Providers"
    case stopwatch = "StopWatch"
    case settings = "Settings & Diagnostics"
    var id: Self { self }
}
```

`ProvidersView` must never prefill API-key text fields from Keychain; it shows only configured/not configured and accepts replacement/deletion. `StopWatchView` lists discovered UUIDs only during an explicit discovery session and requires a selection before binding. `SettingsView` contains refresh interval, login-item control, and redacted diagnostics export.

`DiagnosticExporter` recursively replaces usernames, absolute paths under user
home directories,
CoreBluetooth identifiers, account labels, and values for keys matching
`token|secret|authorization|api[_-]?key` before writing a user-selected JSON
file. Add a unit test whose input contains every category and assert none of
the original sensitive values survives.

- [ ] **Step 6: Build, test, run, and commit**

Run: `swift test`

Expected: PASS.

Run: `swift run tokenlink`

Expected: a TokenLink menu-bar item appears; opening Control Center shows Overview, Providers, StopWatch, and Settings & Diagnostics. Quit from the menu before continuing.

```bash
git add Sources/TokenLinkApp Tests/TokenLinkAppTests
git commit -m "feat: add native TokenLink control center"
```

## Task 12: Package the app and add open-source documentation

**Files:**
- Create: `packaging/Info.plist`
- Create: `scripts/package_app.sh`
- Create: `scripts/privacy_scan.sh`
- Create: `.gitignore`
- Create: `README.md`
- Create: `NOTICE.md`
- Create: `SECURITY.md`
- Create: `CONTRIBUTING.md`
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a privacy-safe `.gitignore`**

```gitignore
.build/
TokenLink.app/
*.log
.DS_Store
.swiftpm/xcode/package.xcworkspace/xcuserdata/
.local/
```

- [ ] **Step 2: Add an app plist**

Use bundle identifier `io.github.phantom5125.tokenlink`, `LSUIElement=true`, minimum system `14.0`, `NSBluetoothAlwaysUsageDescription`, and version `0.1.0`. Do not include device identifiers or local paths.

- [ ] **Step 3: Add deterministic packaging**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
swift build -c release --product tokenlink
bundle="$repo_dir/TokenLink.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$repo_dir/packaging/Info.plist" "$bundle/Contents/Info.plist"
cp "$repo_dir/.build/release/tokenlink" "$bundle/Contents/MacOS/TokenLink"
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
```

- [ ] **Step 4: Add a privacy scanner**

`scripts/privacy_scan.sh` fails when tracked files contain a 36-character CoreBluetooth UUID outside tests/docs fixtures, `/Users/`, `Authorization: Bearer` followed by a non-placeholder value, or common secret prefixes. It allowlists documented service UUIDs and synthetic zero UUIDs.

- [ ] **Step 5: Write public documentation**

README covers requirements, build/run/package, four Provider setup methods, StopWatch binding, v1 Codex-only watch behavior, uninstall, privacy, troubleshooting, and the protocol-v2 roadmap. `SECURITY.md` documents secret handling and private vulnerability reporting. `CONTRIBUTING.md` documents the provider descriptor/fixture/parser/allowlist/test checklist.

`NOTICE.md` includes:

```text
TokenLink derives its M5Stack StopWatch protocol compatibility and firmware roadmap from
codex-micro-stopwatch, Copyright its contributors, MIT License.

TokenLink's provider architecture is inspired by CodexBar by Peter Steinberger and
contributors, MIT License. TokenLink does not bundle or depend on CodexBarCore in v0.1.

GLM quota response handling was checked against zai-org/zai-coding-plugins,
Apache License 2.0. Provider names and trademarks belong to their respective owners.
```

- [ ] **Step 6: Add CI and commit**

CI checks out on `macos-15`, runs `swift build`, `swift test`, `swift format lint --recursive --strict Sources Tests`, and `bash scripts/privacy_scan.sh`.

```bash
git add .gitignore packaging scripts README.md NOTICE.md SECURITY.md CONTRIBUTING.md .github
git commit -m "docs: package and document TokenLink"
```

## Task 13: Complete verification and record honest validation layers

**Files:**
- Create: `docs/validation/2026-08-19-v0.1-validation.md`
- Modify only if verification finds defects: files named by the failing check

- [ ] **Step 1: Run all automated checks from a clean build directory**

```bash
swift package clean
swift build
swift test
swift format lint --recursive --strict Sources Tests
bash scripts/privacy_scan.sh
bash scripts/package_app.sh
plutil -lint TokenLink.app/Contents/Info.plist
codesign --verify --deep --strict TokenLink.app
```

Expected: every command exits 0.

- [ ] **Step 2: Launch the packaged app**

Run: `open TokenLink.app`

Verify the menu bar item, the four control-center routes, missing-credential states, and clean quit. Record observed results; do not infer them from a build.

- [ ] **Step 3: Validate local Codex without exposing credentials**

Use the app's Codex adapter and confirm a real primary remaining percentage and reset time appear. Compare the shape, not account identifiers, against:

```bash
codex app-server --listen stdio://
```

Do not paste real JSON into tracked files.

- [ ] **Step 4: Validate optional real providers only with user-owned credentials**

For Kimi, MiniMax, and GLM, enter keys through TokenLink UI/Keychain, refresh, record only success/failure and sanitized percentages, then delete keys if the user requests. Never put keys on a command line or in shell history.

- [ ] **Step 5: Validate the existing StopWatch without flashing**

Discover the already-running private quota service, require explicit user selection before binding, sync the real Codex snapshot, and observe the watch percentage/reset. Record BLE discovery, bind, ATT ACK, and visible watch update as separate layers. Do not claim C152 validation if hardware is absent.

- [ ] **Step 6: Write the validation report and final commit**

The report table has columns `Layer`, `Command/Action`, `Evidence`, `Status`, and `Limitations`; statuses are only `PASS`, `FAIL`, or `NOT VERIFIED`.

```bash
git add docs/validation/2026-08-19-v0.1-validation.md
git commit -m "test: record v0.1 validation"
```

- [ ] **Step 7: Inspect final repository state**

Run:

```bash
git status --short
git log --oneline --decorate -15
```

Expected: clean worktree and intentional task-by-task commits.
