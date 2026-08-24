import Foundation
import LuxelCore
import Testing

@testable import LuxelApp

@Suite("Notification settings flow")
@MainActor
struct NotificationSettingsFlowTests {
    @Test("first enable requests authorization and reflects the granted system state")
    func firstEnableRequestsAuthorization() async {
        let notifier = NotificationSettingsUserNotifierSpy(
            initialSettings: settings(authorization: .notDetermined),
            requestedSettings: settings(authorization: .authorized, timeSensitive: .enabled)
        )
        let model = makeModel(notifier: notifier)

        await model.refreshAppNotificationSettings()
        await model.setAppNotificationsEnabled(true)

        #expect(model.appNotificationSettings.isAuthorized)
        #expect(model.appNotificationSettings.timeSensitiveSetting == .enabled)
        #expect(notifier.requestCount == 1)
        #expect(notifier.openSettingsCount == 0)
    }

    @Test("denied authorization opens macOS settings instead of faking an enabled toggle")
    func deniedAuthorizationOpensSettings() async {
        let notifier = NotificationSettingsUserNotifierSpy(
            initialSettings: settings(authorization: .denied)
        )
        let model = makeModel(notifier: notifier)

        await model.refreshAppNotificationSettings()
        await model.setAppNotificationsEnabled(true)

        #expect(!model.appNotificationSettings.isAuthorized)
        #expect(notifier.requestCount == 0)
        #expect(notifier.openSettingsCount == 1)
    }

    @Test("editor export notifications respect the per-type preference")
    func exportCompletionPreference() async {
        let notifier = NotificationSettingsUserNotifierSpy(
            initialSettings: settings(authorization: .authorized)
        )
        let model = makeModel(notifier: notifier)
        let fileURL = URL(fileURLWithPath: "/tmp/export.mp4")

        model.settings.exportCompletionNotificationsEnabled = false
        await model.notifyExportCompleted(fileURLs: [fileURL])
        model.settings.exportCompletionNotificationsEnabled = true
        await model.notifyExportCompleted(fileURLs: [fileURL])

        #expect(notifier.exportNotifications == [[fileURL]])
    }

    private func makeModel(notifier: any UserNotifier) -> LuxelMenuModel {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/LuxelNotificationTests")
        return LuxelMenuModel(
            settingsStore: NotificationSettingsStore(
                settings: AppSettings.defaults(recordingsDirectory: recordingsDirectory)
            ),
            userNotifier: notifier
        )
    }

    private func settings(
        authorization: AppNotificationAuthorizationStatus,
        timeSensitive: AppNotificationDeliverySetting = .disabled
    ) -> AppNotificationSettings {
        AppNotificationSettings(
            authorizationStatus: authorization,
            timeSensitiveSetting: timeSensitive
        )
    }
}

private struct NotificationSettingsStore: SettingsStore {
    let settings: AppSettings

    func load() throws -> AppSettings { settings }
    func save(_ settings: AppSettings) throws {}
}

private final class NotificationSettingsUserNotifierSpy: UserNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var currentSettings: AppNotificationSettings
    private let requestedSettings: AppNotificationSettings
    private var storedRequestCount = 0
    private var storedOpenSettingsCount = 0
    private var storedExportNotifications: [[URL]] = []

    init(
        initialSettings: AppNotificationSettings,
        requestedSettings: AppNotificationSettings? = nil
    ) {
        currentSettings = initialSettings
        self.requestedSettings = requestedSettings ?? initialSettings
    }

    var requestCount: Int { lock.withLock { storedRequestCount } }
    var openSettingsCount: Int { lock.withLock { storedOpenSettingsCount } }
    var exportNotifications: [[URL]] { lock.withLock { storedExportNotifications } }

    func notificationSettings() async -> AppNotificationSettings {
        lock.withLock { currentSettings }
    }

    func requestAuthorization() async -> AppNotificationSettings {
        lock.withLock {
            storedRequestCount += 1
            currentSettings = requestedSettings
            return currentSettings
        }
    }

    @MainActor
    func openNotificationSettings() {
        lock.withLock {
            storedOpenSettingsCount += 1
        }
    }

    func notifyExportCompleted(fileURL: URL, presetName: String) async throws {}

    func notifyExportCompleted(fileURLs: [URL], sourceName: String) async throws {
        lock.withLock {
            storedExportNotifications.append(fileURLs)
        }
    }
}
