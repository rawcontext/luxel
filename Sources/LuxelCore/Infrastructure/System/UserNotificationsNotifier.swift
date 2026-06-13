import AppKit
import Foundation
import UserNotifications

public struct UserNotificationsNotifier: UserNotifier, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter
    private let shouldNotifyRecordingFinished: @Sendable () async -> Bool

    public init(
        notificationCenter: UNUserNotificationCenter = .current(),
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
        let isAuthorized = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard isAuthorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Export Complete"
        content.body = "\(presetName) saved \(fileURL.lastPathComponent)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "luxel.export.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }

    public func notifyRecordingAutoStopped(duration: TimeInterval) async throws {
        guard await shouldNotifyRecordingFinished() else {
            return
        }

        let isAuthorized = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard isAuthorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Recording Finished"
        content.body = "Recording finished - \(Self.durationText(duration))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "luxel.recording.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }

        return "\(minutes):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
