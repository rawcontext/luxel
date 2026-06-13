import Foundation
import UserNotifications

public struct UserNotificationsNotifier: UserNotifier, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter

    public init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
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
}
