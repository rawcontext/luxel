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

    public func notificationSettings() async -> AppNotificationSettings {
        guard let notificationCenter = resolvedNotificationCenter else {
            return .unavailable
        }

        let settings = await notificationCenter.notificationSettings()
        return AppNotificationSettings(
            authorizationStatus: settings.authorizationStatus.appNotificationStatus,
            timeSensitiveSetting: settings.timeSensitiveSetting.appNotificationSetting
        )
    }

    public func requestAuthorization() async -> AppNotificationSettings {
        guard let notificationCenter = resolvedNotificationCenter else {
            return .unavailable
        }

        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
        return await notificationSettings()
    }

    public func notifyExportCompleted(fileURL: URL, presetName: String) async throws {
        try await notifyExportCompleted(fileURLs: [fileURL], sourceName: presetName)
    }

    public func notifyExportCompleted(fileURLs: [URL], sourceName: String) async throws {
        guard !fileURLs.isEmpty,
            let notificationCenter = resolvedNotificationCenter,
            await notificationSettings().isAuthorized
        else {
            return
        }

        let content = Self.exportCompletedContent(
            fileURLs: fileURLs,
            sourceName: sourceName
        )
        let request = UNNotificationRequest(
            identifier: "luxel.export.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
    }

    static func exportCompletedContent(
        fileURLs: [URL],
        sourceName: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = LuxelLocalization.string(
            "notifications.exportComplete.title",
            defaultValue: "Export Complete")
        if fileURLs.count == 1, let fileURL = fileURLs.first {
            content.body = LuxelLocalization.format(
                "notifications.exportComplete.body",
                defaultValue: "%@ saved %@",
                sourceName,
                fileURL.lastPathComponent
            )
        } else {
            content.body = LuxelLocalization.format(
                "notifications.exportComplete.batchBody",
                defaultValue: "%@ saved %@ files",
                sourceName,
                String(fileURLs.count)
            )
        }
        content.categoryIdentifier = ExportCompletionNotificationIdentifiers.category
        content.threadIdentifier = ExportCompletionNotificationIdentifiers.category
        content.userInfo = [
            ExportCompletionNotificationIdentifiers.filePathsUserInfoKey:
                fileURLs.map(\.path)
        ]
        content.sound = .default
        return content
    }

    public func notifyRecordingAutoStopped(duration: TimeInterval) async throws {
        guard let notificationCenter = resolvedNotificationCenter else {
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

    private var resolvedNotificationCenter: UNUserNotificationCenter? {
        notificationCenter ?? Self.currentNotificationCenter()
    }
}

extension UNAuthorizationStatus {
    fileprivate var appNotificationStatus: AppNotificationAuthorizationStatus {
        switch self {
        case .notDetermined:
            .notDetermined
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        @unknown default:
            .unavailable
        }
    }
}

extension UNNotificationSetting {
    fileprivate var appNotificationSetting: AppNotificationDeliverySetting {
        switch self {
        case .enabled:
            .enabled
        case .disabled:
            .disabled
        case .notSupported:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}
