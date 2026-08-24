import AppKit
import Foundation
import LuxelCore

struct AppKitUserNotifier: UserNotifier, @unchecked Sendable {
    private let upstream: UserNotificationsNotifier

    init(upstream: UserNotificationsNotifier = UserNotificationsNotifier()) {
        self.upstream = upstream
    }

    func notificationSettings() async -> AppNotificationSettings {
        await upstream.notificationSettings()
    }

    func requestAuthorization() async -> AppNotificationSettings {
        await upstream.requestAuthorization()
    }

    @MainActor
    func openNotificationSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func notifyExportCompleted(fileURL: URL, presetName: String) async throws {
        try await upstream.notifyExportCompleted(fileURL: fileURL, presetName: presetName)
    }

    func notifyExportCompleted(fileURLs: [URL], sourceName: String) async throws {
        try await upstream.notifyExportCompleted(fileURLs: fileURLs, sourceName: sourceName)
    }

    func notifyRecordingAutoStopped(duration: TimeInterval) async throws {
        try await upstream.notifyRecordingAutoStopped(duration: duration)
    }
}
