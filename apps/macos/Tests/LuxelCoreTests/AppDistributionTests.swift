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

    @Test("Developer ID distribution keeps updater and CLI installer outside StoreKit")
    func developerIDDistributionKeepsUpdaterAndCLIInstallerOutsideStoreKit() {
        let capabilities = AppDistribution.developerID.capabilities

        #expect(capabilities.includesSparkleUpdater)
        #expect(!capabilities.usesStoreKitEntitlements)
        #expect(capabilities.allowsCommandLineToolInstaller)
    }

    @Test("Mac App Store distribution uses StoreKit and excludes external updater surfaces")
    func macAppStoreDistributionUsesStoreKitAndExcludesExternalUpdaterSurfaces() {
        let capabilities = AppDistribution.macAppStore.capabilities

        #expect(!capabilities.includesSparkleUpdater)
        #expect(capabilities.usesStoreKitEntitlements)
        #expect(!capabilities.allowsCommandLineToolInstaller)
    }
}
