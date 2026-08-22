import Foundation

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