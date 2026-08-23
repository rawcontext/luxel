import LuxelCore
import Testing

@Suite("App distribution")
struct AppDistributionTests {
    @Test("current distribution follows active compilation condition")
    func currentDistributionFollowsActiveCompilationCondition() {
        #if LUXEL_MAC_APP_STORE
            #expect(AppDistribution.current == .macAppStore)
        #else
            #expect(AppDistribution.current == .developerID)
        #endif
    }

    @Test("Developer ID distribution keeps updater outside StoreKit")
    func developerIDDistributionKeepsUpdaterOutsideStoreKit() {
        let capabilities = AppDistribution.developerID.capabilities

        #expect(capabilities.includesSparkleUpdater)
        #expect(!capabilities.usesStoreKitEntitlements)
    }

    @Test("Mac App Store distribution uses StoreKit")
    func macAppStoreDistributionUsesStoreKit() {
        let capabilities = AppDistribution.macAppStore.capabilities

        #expect(!capabilities.includesSparkleUpdater)
        #expect(capabilities.usesStoreKitEntitlements)
    }
}
