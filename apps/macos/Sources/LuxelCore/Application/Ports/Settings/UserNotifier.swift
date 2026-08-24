import Foundation

public enum AppNotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public enum AppNotificationDeliverySetting: Equatable, Sendable {
    case enabled
    case disabled
    case unavailable
}

public struct AppNotificationSettings: Equatable, Sendable {
    public let authorizationStatus: AppNotificationAuthorizationStatus
    public let timeSensitiveSetting: AppNotificationDeliverySetting

    public init(
        authorizationStatus: AppNotificationAuthorizationStatus,
        timeSensitiveSetting: AppNotificationDeliverySetting
    ) {
        self.authorizationStatus = authorizationStatus
        self.timeSensitiveSetting = timeSensitiveSetting
    }

    public static let unavailable = AppNotificationSettings(
        authorizationStatus: .unavailable,
        timeSensitiveSetting: .unavailable
    )

    public var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
}

public enum ExportCompletionNotificationIdentifiers {
    public static let category = "media.luxel.export-complete"
    public static let showInFinderAction = "media.luxel.export-complete.show-in-finder"
    public static let filePathsUserInfoKey = "media.luxel.export-complete.file-paths"
}

public protocol UserNotifier: Sendable {
    func notificationSettings() async -> AppNotificationSettings
    func requestAuthorization() async -> AppNotificationSettings
    @MainActor func openNotificationSettings()
    func notifyExportCompleted(fileURL: URL, presetName: String) async throws
    func notifyExportCompleted(fileURLs: [URL], sourceName: String) async throws
    func notifyRecordingAutoStopped(duration: TimeInterval) async throws
}

extension UserNotifier {
    public func notificationSettings() async -> AppNotificationSettings { .unavailable }
    public func requestAuthorization() async -> AppNotificationSettings { .unavailable }
    @MainActor public func openNotificationSettings() {}

    public func notifyExportCompleted(fileURLs: [URL], sourceName: String) async throws {
        guard let fileURL = fileURLs.first else {
            return
        }
        try await notifyExportCompleted(fileURL: fileURL, presetName: sourceName)
    }

    public func notifyRecordingAutoStopped(duration: TimeInterval) async throws {}
}
