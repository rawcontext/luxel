public struct UpdateSettingsPresentation: Equatable, Sendable {
    public let showsDeveloperIDUpdateControls: Bool
    public let automaticInstallToggleEnabled: Bool
    public let canCheckNow: Bool
    public let statusText: String
    public let networkPolicyText: String
    public let checkNowHelp: String

    public init(
        preferences: UpdatePreferences,
        distribution: AppDistribution,
        updateCheckingAvailable: Bool = false
    ) {
        showsDeveloperIDUpdateControls = distribution.capabilities.includesSparkleUpdater
        automaticInstallToggleEnabled =
            showsDeveloperIDUpdateControls
            && preferences.automaticallyCheckForUpdates
        canCheckNow = showsDeveloperIDUpdateControls && updateCheckingAvailable

        if showsDeveloperIDUpdateControls {
            statusText =
                updateCheckingAvailable
                ? LuxelLocalization.string(
                    "updates.status.readyToCheck",
                    defaultValue: "Ready to Check")
                : LuxelLocalization.string(
                    "updates.status.comingSoon",
                    defaultValue: "Update Checks Coming Soon")
            networkPolicyText =
                if preferences.automaticallyCheckForUpdates {
                    LuxelLocalization.string(
                        "updates.networkPolicy.enabled",
                        defaultValue:
                            "Luxel only touches the network to check for updates, and only if enabled.")
                } else {
                    LuxelLocalization.string(
                        "updates.networkPolicy.disabled",
                        defaultValue:
                            "Automatic update checks are off; Luxel will not contact the update server.")
                }
            checkNowHelp =
                updateCheckingAvailable
                ? LuxelLocalization.string(
                    "updates.checkNow.help",
                    defaultValue: "Check for a Luxel update now.")
                : LuxelLocalization.string(
                    "updates.checkNow.unavailableHelp",
                    defaultValue: "Update checks will be available when Sparkle is integrated.")
        } else {
            statusText = LuxelLocalization.string(
                "updates.status.macAppStore",
                defaultValue: "Updates Handled by the Mac App Store")
            networkPolicyText = LuxelLocalization.string(
                "updates.networkPolicy.macAppStore",
                defaultValue: "This build does not include the Developer ID updater.")
            checkNowHelp = ""
        }
    }
}
