import AppKit
import Foundation
@preconcurrency import UserNotifications

public enum VoiceDetectionNotificationIdentifiers {
    public static let category = "media.luxel.speech-detection-prompt"
    public static let request = "media.luxel.speech-detection-prompt.active"
    public static let startRecordingAction = "media.luxel.speech-detection-prompt.start-recording"
    public static let dismissAction = "media.luxel.speech-detection-prompt.dismiss"
}

public struct UserNotificationsSpeechPromptNotifier:
    VoiceRecordingPromptNotifying,
    @unchecked Sendable {
    private let center: (any VoiceRecordingPromptNotificationCenter)?

    public init(notificationCenter: UNUserNotificationCenter? = nil) {
        let resolvedCenter = notificationCenter ?? Self.currentNotificationCenter()
        center = resolvedCenter.map(UserNotificationCenterPromptClient.init)
    }

    init(center: any VoiceRecordingPromptNotificationCenter) {
        self.center = center
    }

    public func authorizationStatus() async -> VoiceDetectionAuthorizationStatus {
        guard let center else {
            return .denied
        }
        return await center.authorizationStatus()
    }

    public func requestAuthorization() async -> VoiceDetectionAuthorizationStatus {
        guard let center else {
            return .denied
        }
        return await center.requestAuthorization()
    }

    @MainActor
    public func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func postPrompt() async throws {
        guard let center else {
            return
        }

        await removePrompt()

        let content = UNMutableNotificationContent()
        content.title = LuxelLocalization.string(
            "notifications.speechDetected.title",
            defaultValue: "Speech detected"
        )
        content.body = LuxelLocalization.string(
            "notifications.speechDetected.body",
            defaultValue: "Start an audio recording?"
        )
        content.categoryIdentifier = VoiceDetectionNotificationIdentifiers.category
        content.sound = .default

        try await center.add(
            UNNotificationRequest(
                identifier: VoiceDetectionNotificationIdentifiers.request,
                content: content,
                trigger: nil
            )
        )
    }

    public func removePrompt() async {
        guard let center else {
            return
        }

        let identifiers = [VoiceDetectionNotificationIdentifiers.request]
        await center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func currentNotificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return .current()
    }
}

protocol VoiceRecordingPromptNotificationCenter: Sendable {
    func authorizationStatus() async -> VoiceDetectionAuthorizationStatus
    func requestAuthorization() async -> VoiceDetectionAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
}

private struct UserNotificationCenterPromptClient:
    VoiceRecordingPromptNotificationCenter,
    @unchecked Sendable {
    let center: UNUserNotificationCenter

    func authorizationStatus() async -> VoiceDetectionAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus.voiceDetectionStatus
    }

    func requestAuthorization() async -> VoiceDetectionAuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

private extension UNAuthorizationStatus {
    var voiceDetectionStatus: VoiceDetectionAuthorizationStatus {
        switch self {
        case .notDetermined:
            .notDetermined
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        @unknown default:
            .denied
        }
    }
}
