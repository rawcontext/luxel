public enum PermissionGuidanceAction: Codable, Equatable, Sendable {
    case request
    case openSettings
}

public struct PermissionGuidance: Codable, Equatable, Sendable {
    public let title: String
    public let message: String
    public let actionTitle: String
    public let action: PermissionGuidanceAction

    public init(
        title: String,
        message: String,
        actionTitle: String,
        action: PermissionGuidanceAction
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
}

public struct PermissionGuidanceService: Sendable {
    public init() {}

    public func guidance(for permission: SystemPermission, status: PermissionStatus) -> PermissionGuidance {
        switch permission {
        case .screenRecording:
            screenRecordingGuidance(status: status)
        case .microphone:
            microphoneGuidance(status: status)
        }
    }

    private func screenRecordingGuidance(status: PermissionStatus) -> PermissionGuidance {
        switch status {
        case .authorized:
            PermissionGuidance(
                title: "Screen Recording Enabled",
                message: "Luxel can record your screen.",
                actionTitle: "OK",
                action: .request
            )
        case .notDetermined, .denied, .restricted, .unknown:
            PermissionGuidance(
                title: "Screen Recording Permission",
                message: "Luxel needs Screen Recording permission to capture displays, windows, and selected areas. Continue, enable Luxel in System Settings if prompted, then quit and reopen Luxel.",
                actionTitle: "Continue",
                action: .request
            )
        }
    }

    private func microphoneGuidance(status: PermissionStatus) -> PermissionGuidance {
        switch status {
        case .notDetermined:
            PermissionGuidance(
                title: "Microphone Permission",
                message: "Luxel needs Microphone permission when audio recording is enabled.",
                actionTitle: "Continue",
                action: .request
            )
        case .denied, .restricted, .unknown:
            PermissionGuidance(
                title: "Microphone Permission",
                message: "Luxel needs Microphone permission when audio recording is enabled. Open System Settings and allow Luxel to use the microphone.",
                actionTitle: "Open Settings",
                action: .openSettings
            )
        case .authorized:
            PermissionGuidance(
                title: "Microphone Enabled",
                message: "Luxel can record microphone audio.",
                actionTitle: "OK",
                action: .request
            )
        }
    }
}
