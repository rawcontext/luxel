import LuxelCore
import Testing

@Suite("Update settings presentation")
struct UpdateSettingsPresentationTests {
    @Test("Developer ID updates show disabled coming soon checks")
    func developerIDUpdatesShowComingSoonChecks() {
        let presentation = UpdateSettingsPresentation(
            preferences: .defaults,
            distribution: .developerID
        )

        #expect(presentation.showsDeveloperIDUpdateControls)
        #expect(presentation.automaticInstallToggleEnabled)
        #expect(!presentation.canCheckNow)
        #expect(presentation.statusText == "Update Checks Coming Soon")
        #expect(presentation.networkPolicyText == "Luxel only touches the network to check for updates, and only if enabled.")
        #expect(presentation.checkNowHelp == "Update checks will be available when Sparkle is integrated.")
    }

    @Test("disabled automatic checks disable automatic install and network contact")
    func disabledAutomaticChecksDisableInstallAndNetworkContact() {
        let presentation = UpdateSettingsPresentation(
            preferences: UpdatePreferences(
                automaticallyCheckForUpdates: false,
                automaticallyDownloadAndInstall: true,
                channel: .beta
            ),
            distribution: .developerID
        )

        #expect(presentation.showsDeveloperIDUpdateControls)
        #expect(!presentation.automaticInstallToggleEnabled)
        #expect(!presentation.canCheckNow)
        #expect(presentation.networkPolicyText == "Automatic update checks are off; Luxel will not contact the update server.")
    }

    @Test("Mac App Store hides Developer ID updater controls")
    func macAppStoreHidesDeveloperIDUpdaterControls() {
        let presentation = UpdateSettingsPresentation(
            preferences: .defaults,
            distribution: .macAppStore
        )

        #expect(!presentation.showsDeveloperIDUpdateControls)
        #expect(!presentation.automaticInstallToggleEnabled)
        #expect(!presentation.canCheckNow)
        #expect(presentation.statusText == "Updates Handled by the Mac App Store")
        #expect(presentation.networkPolicyText == "This build does not include the Developer ID updater.")
        #expect(presentation.checkNowHelp == "")
    }
}
