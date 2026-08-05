import Testing
@testable import WolfGrid

struct StatsLiveCountPolicyTests {
    @Test func successfulEmptyRemoteResultOverridesStaleCache() {
        let cachedKeys: Set<String> = ["stale-imported-lead"]

        #expect(
            StatsLiveCountPolicy.resolvedCount(
                remoteKeys: Set<String>(),
                cachedKeys: cachedKeys
            ) == 0
        )
    }

    @Test func cacheIsOnlyUsedWhenRemoteDataIsUnavailable() {
        let cachedKeys: Set<String> = ["field-lead-1", "field-lead-2"]

        #expect(
            StatsLiveCountPolicy.resolvedCount(
                remoteKeys: nil,
                cachedKeys: cachedKeys
            ) == 2
        )
    }

    @Test func onlyExplicitFieldLeadsAreSafeForStatsCacheFallback() {
        #expect(StatsLiveCountPolicy.isFieldLead(leadKind: "field"))
        #expect(!StatsLiveCountPolicy.isFieldLead(leadKind: "scraped"))
        #expect(!StatsLiveCountPolicy.isFieldLead(leadKind: nil))
    }
}
