public enum AppDistribution: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case developerID
    case macAppStore

    public static var current: AppDistribution {
        #if LUXEL_MAC_APP_STORE
        .macAppStore
        #else
        .developerID
        #endif
    }

    public var id: String {
        rawValue
    }

    public var capabilities: AppDistributionCapabilities {
        switch self {
        case .developerID:
            AppDistributionCapabilities(
                includesSparkleUpdater: true,
                usesStoreKitEntitlements: false,
                allowsCommandLineToolInstaller: true
            )
        case .macAppStore:
            AppDistributionCapabilities(
                includesSparkleUpdater: false,
                usesStoreKitEntitlements: true,
                allowsCommandLineToolInstaller: false
            )
        }
    }
}

public struct AppDistributionCapabilities: Equatable, Sendable {
    public let includesSparkleUpdater: Bool
    public let usesStoreKitEntitlements: Bool
    public let allowsCommandLineToolInstaller: Bool

    public init(
        includesSparkleUpdater: Bool,
        usesStoreKitEntitlements: Bool,
        allowsCommandLineToolInstaller: Bool
    ) {
        self.includesSparkleUpdater = includesSparkleUpdater
        self.usesStoreKitEntitlements = usesStoreKitEntitlements
        self.allowsCommandLineToolInstaller = allowsCommandLineToolInstaller
    }
}
