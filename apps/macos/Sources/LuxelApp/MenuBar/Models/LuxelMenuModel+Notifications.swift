import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshAppNotificationSettings() async {
        appNotificationSettings = await userNotifier.notificationSettings()
    }

    func setAppNotificationsEnabled(_ isEnabled: Bool) async {
        if isEnabled {
            switch appNotificationSettings.authorizationStatus {
            case .notDetermined, .unavailable:
                appNotificationSettings = await userNotifier.requestAuthorization()
            case .denied:
                userNotifier.openNotificationSettings()
            case .authorized:
                break
            }
        } else if appNotificationSettings.authorizationStatus == .authorized {
            userNotifier.openNotificationSettings()
        }

        await refreshAppNotificationSettings()
        scheduleVoiceDetectionReconciliation()
    }

    func openAppNotificationSettings() async {
        userNotifier.openNotificationSettings()
        await refreshAppNotificationSettings()
    }

    func notifyExportCompleted(fileURLs: [URL]) async {
        guard settings.exportCompletionNotificationsEnabled else {
            return
        }

        try? await userNotifier.notifyExportCompleted(
            fileURLs: fileURLs,
            sourceName: appMetadata.displayName
        )
    }
}
