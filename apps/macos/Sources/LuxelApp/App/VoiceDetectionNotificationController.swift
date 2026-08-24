import Foundation
import LuxelCore
@preconcurrency import UserNotifications

final class LuxelNotificationController: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    private let actionHandler: @Sendable (VoiceDetectionPromptAction) -> Void
    private let exportHandler: @Sendable ([URL]) -> Void

    init(
        actionHandler: @escaping @Sendable (VoiceDetectionPromptAction) -> Void,
        exportHandler: @escaping @Sendable ([URL]) -> Void = { _ in }
    ) {
        self.actionHandler = actionHandler
        self.exportHandler = exportHandler
    }

    func install(on center: UNUserNotificationCenter) {
        center.setNotificationCategories([Self.category, Self.exportCategory])
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            Self.presentationOptions(
                categoryIdentifier: notification.request.content.categoryIdentifier
            )
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleResponse(
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo,
            completionHandler: completionHandler
        )
    }

    func handleResponse(
        categoryIdentifier: String,
        actionIdentifier: String,
        userInfo: [AnyHashable: Any] = [:],
        completionHandler: () -> Void
    ) {
        defer {
            completionHandler()
        }

        if categoryIdentifier == VoiceDetectionNotificationIdentifiers.category,
            let action = Self.action(for: actionIdentifier)
        {
            actionHandler(action)
        } else if categoryIdentifier == ExportCompletionNotificationIdentifiers.category,
            Self.isExportRevealAction(actionIdentifier)
        {
            let fileURLs = Self.exportedFileURLs(userInfo: userInfo)
            if !fileURLs.isEmpty {
                exportHandler(fileURLs)
            }
        }
    }

    static func presentationOptions(
        categoryIdentifier: String
    ) -> UNNotificationPresentationOptions {
        guard
            categoryIdentifier == VoiceDetectionNotificationIdentifiers.category
                || categoryIdentifier == ExportCompletionNotificationIdentifiers.category
        else {
            return []
        }
        return [.banner, .list, .sound]
    }

    static func action(for identifier: String) -> VoiceDetectionPromptAction? {
        switch identifier {
        case VoiceDetectionNotificationIdentifiers.startRecordingAction:
            .startRecording
        case VoiceDetectionNotificationIdentifiers.dismissAction,
            UNNotificationDismissActionIdentifier:
            .dismiss
        case UNNotificationDefaultActionIdentifier:
            .defaultAction
        default:
            nil
        }
    }

    static var category: UNNotificationCategory {
        let startRecording = UNNotificationAction(
            identifier: VoiceDetectionNotificationIdentifiers.startRecordingAction,
            title: LuxelLocalization.string(
                "notifications.speechDetected.startRecording",
                defaultValue: "Start Recording"
            ),
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: VoiceDetectionNotificationIdentifiers.dismissAction,
            title: LuxelLocalization.string(
                "notifications.speechDetected.dismiss",
                defaultValue: "Dismiss"
            ),
            options: []
        )
        return UNNotificationCategory(
            identifier: VoiceDetectionNotificationIdentifiers.category,
            actions: [startRecording, dismiss],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
    }

    static var exportCategory: UNNotificationCategory {
        let showInFinder = UNNotificationAction(
            identifier: ExportCompletionNotificationIdentifiers.showInFinderAction,
            title: LuxelLocalization.string(
                "Show in Finder",
                defaultValue: "Show in Finder"
            ),
            options: []
        )
        return UNNotificationCategory(
            identifier: ExportCompletionNotificationIdentifiers.category,
            actions: [showInFinder],
            intentIdentifiers: [],
            options: []
        )
    }

    static func isExportRevealAction(_ identifier: String) -> Bool {
        identifier == UNNotificationDefaultActionIdentifier
            || identifier == ExportCompletionNotificationIdentifiers.showInFinderAction
    }

    static func exportedFileURLs(userInfo: [AnyHashable: Any]) -> [URL] {
        guard
            let paths = userInfo[
                ExportCompletionNotificationIdentifiers.filePathsUserInfoKey
            ] as? [String]
        else {
            return []
        }
        return paths.filter { !$0.isEmpty }.map(URL.init(fileURLWithPath:))
    }
}
