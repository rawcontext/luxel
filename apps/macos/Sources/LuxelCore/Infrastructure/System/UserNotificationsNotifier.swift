import AppKit
import Foundation
import UserNotifications

public struct UserNotificationsNotifier: UserNotifier, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter?
    private let shouldNotifyRecordingFinished: @Sendable () async -> Bool

    public init(
        notificationCenter: UNUserNotificationCenter? = nil,
        shouldNotifyRecordingFinished: @escaping @Sendable () async -> Bool = {
            await MainActor.run {
                !NSApplication.shared.isActive
            }
        }
    ) {
        self.notificationCenter = notificationCenter
        self.shouldNotifyRecordingFinished = shouldNotifyRecordingFinished
    }

    public func notifyExportCompleted(fileURL: URL, presetName: String) async throws {
        guard let notificationCenter = notificationCenter ?? Self.currentNotificationCenter() else {
            return
        }

        let isAuthorized = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard isAuthorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = LuxelLocalization.string(
            "notifications.exportComplete.title",
            defaultValue: "Export Complete")
        content.body = LuxelLocalization.format(
            "notifications.exportComplete.body",
            defaultValue: "%@ saved %@",
            presetName,
            fileURL.lastPathComponent)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "luxel.export.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }

    public func notifyRecordingAutoStopped(duration: TimeInterval) async throws {
        guard let notificationCenter = notificationCenter ?? Self.currentNotificationCenter() else {
            return
        }

        guard await shouldNotifyRecordingFinished() else {
            return
        }

        let isAuthorized = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard isAuthorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = LuxelLocalization.string(
            "notifications.recordingFinished.title",
            defaultValue: "Recording Finished")
        content.body = LuxelLocalization.format(
            "notifications.recordingFinished.body",
            defaultValue: "Recording finished - %@",
            RecordingDurationFormatter.elapsedTime(duration))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "luxel.recording.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }

    private static func currentNotificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }

        return .current()
    }
}
