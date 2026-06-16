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
        automaticInstallToggleEnabled = showsDeveloperIDUpdateControls
            && preferences.automaticallyCheckForUpdates
        canCheckNow = showsDeveloperIDUpdateControls && updateCheckingAvailable

        if showsDeveloperIDUpdateControls {
            statusText = updateCheckingAvailable ? "Ready to Check" : "Update Checks Coming Soon"
            networkPolicyText = if preferences.automaticallyCheckForUpdates {
                "Luxel only touches the network to check for updates, and only if enabled."
            } else {
                "Automatic update checks are off; Luxel will not contact the update server."
            }
            checkNowHelp = updateCheckingAvailable
                ? "Check for a Luxel update now."
                : "Update checks will be available when Sparkle is integrated."
        } else {
            statusText = "Updates Handled by the Mac App Store"
            networkPolicyText = "This build does not include the Developer ID updater."
            checkNowHelp = ""
        }
    }
}
