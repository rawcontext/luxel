import Foundation
import LuxelCore
@preconcurrency import UserNotifications

final class VoiceDetectionNotificationController: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    private let actionHandler: @Sendable (VoiceDetectionPromptAction) -> Void

    init(actionHandler: @escaping @Sendable (VoiceDetectionPromptAction) -> Void) {
        self.actionHandler = actionHandler
    }

    func install(on center: UNUserNotificationCenter) {
        center.setNotificationCategories([Self.category])
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
            completionHandler: completionHandler
        )
    }

    func handleResponse(
        categoryIdentifier: String,
        actionIdentifier: String,
        completionHandler: () -> Void
    ) {
        defer {
            completionHandler()
        }

        guard categoryIdentifier == VoiceDetectionNotificationIdentifiers.category,
            let action = Self.action(for: actionIdentifier)
        else {
            return
        }

        actionHandler(action)
    }

    static func presentationOptions(
        categoryIdentifier: String
    ) -> UNNotificationPresentationOptions {
        guard categoryIdentifier == VoiceDetectionNotificationIdentifiers.category else {
            return []
        }
        return [.banner, .sound]
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
}
