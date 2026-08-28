public enum PermissionGuidanceAction: Codable, Equatable, Sendable {
    case request
    case openSettings
    case enableSource
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

    public func guidance(for permission: SystemPermission, status: PermissionStatus)
        -> PermissionGuidance {
        switch permission {
        case .screenRecording:
            screenRecordingGuidance(status: status)
        case .microphone:
            microphoneGuidance(status: status)
        case .camera:
            cameraGuidance(status: status)
        case .inputMonitoring:
            inputMonitoringGuidance(status: status)
        }
    }

    public func guidance(
        for source: CapturePermissionSource,
        presentation: CaptureSourcePermissionPresentation,
        status: PermissionStatus
    ) -> PermissionGuidance {
        switch source {
        case .screenPixels:
            screenRecordingGuidance(status: status)
        case .systemAudio:
            systemAudioGuidance(presentation: presentation, status: status)
        case .microphone:
            microphoneGuidance(presentation: presentation, status: status)
        case .camera:
            cameraGuidance(presentation: presentation, status: status)
        }
    }

    private func screenRecordingGuidance(status: PermissionStatus) -> PermissionGuidance {
        switch status {
        case .authorized:
            PermissionGuidance(
                title: "Screen capture ready",
                message: "Luxel can record your screen and system sound.",
                actionTitle: "OK",
                action: .request
            )
        case .notDetermined:
            PermissionGuidance(
                title: "Screen capture is off",
                message: "Turn Luxel on in Screen & System Audio Recording. "
                    + "If Luxel is not listed, click + and add the app.",
                actionTitle: LuxelLocalization.string(
                    "permissions.screen.enable",
                    defaultValue: "Enable Capture"),
                action: .request
            )
        case .denied, .restricted, .unknown:
            PermissionGuidance(
                title: "Screen capture is off",
                message: "Turn Luxel on in Screen & System Audio Recording. "
                    + "If Luxel is not listed, click + and add the app.",
                actionTitle: "Open System Settings",
                action: .openSettings
            )
        }
    }

    private func systemAudioGuidance(
        presentation: CaptureSourcePermissionPresentation,
        status: PermissionStatus
    ) -> PermissionGuidance {
        switch presentation.phase {
        case .ready:
            PermissionGuidance(
                title: presentation.title,
                message: presentation.message,
                actionTitle: "OK",
                action: .request
            )
        case .offByUser:
            PermissionGuidance(
                title: presentation.title,
                message: presentation.message,
                actionTitle: presentation.actionTitle,
                action: .enableSource
            )
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
            .pausedByMacOS, .blocked:
            switch status {
            case .notDetermined:
                PermissionGuidance(
                    title: presentation.title,
                    message: "System sound uses macOS Screen & System Audio Recording. "
                        + "If Luxel is not listed, click + and add the app.",
                    actionTitle: LuxelLocalization.string(
                        "permissions.systemAudio.enable",
                        defaultValue: "Enable System Sound"),
                    action: .request
                )
            case .authorized:
                PermissionGuidance(
                    title: presentation.title,
                    message: presentation.message,
                    actionTitle: presentation.actionTitle,
                    action: .enableSource
                )
            case .denied, .restricted, .unknown:
                PermissionGuidance(
                    title: presentation.title,
                    message: "Turn Luxel on for system audio in Screen & System Audio Recording. "
                        + "If Luxel is not listed, click + and add the app.",
                    actionTitle: "Open System Settings",
                    action: .openSettings
                )
            }
        }
    }

    private func microphoneGuidance(status: PermissionStatus) -> PermissionGuidance {
        switch status {
        case .notDetermined:
            PermissionGuidance(
                title: "Microphone is off",
                message: "Allow microphone access to add your voice to recordings.",
                actionTitle: LuxelLocalization.string(
                    "permissions.microphone.enable",
                    defaultValue: "Enable Mic"),
                action: .request
            )
        case .denied, .restricted, .unknown:
            PermissionGuidance(
                title: "Microphone is off",
                message: "Allow microphone access to add your voice to recordings.",
                actionTitle: "Open System Settings",
                action: .openSettings
            )
        case .authorized:
            PermissionGuidance(
                title: "Microphone on",
                message: "Microphone audio will be included with recordings.",
                actionTitle: "OK",
                action: .request
            )
        }
    }

    private func microphoneGuidance(
        presentation: CaptureSourcePermissionPresentation,
        status: PermissionStatus
    ) -> PermissionGuidance {
        sourceGuidance(presentation: presentation) { microphoneGuidance(status: status) }
    }

    private func cameraGuidance(status: PermissionStatus) -> PermissionGuidance {
        switch status {
        case .notDetermined:
            PermissionGuidance(
                title: "Camera is off",
                message: "Allow camera access to add your camera overlay.",
                actionTitle: LuxelLocalization.string(
                    "permissions.camera.enable",
                    defaultValue: "Enable Camera"),
                action: .request
            )
        case .denied, .restricted, .unknown:
            PermissionGuidance(
                title: "Camera is off",
                message: "Allow camera access to add your camera overlay.",
                actionTitle: "Open System Settings",
                action: .openSettings
            )
        case .authorized:
            PermissionGuidance(
                title: "Camera on",
                message: "Camera overlay will be included with recordings.",
                actionTitle: "OK",
                action: .request
            )
        }
    }

    private func cameraGuidance(
        presentation: CaptureSourcePermissionPresentation,
        status: PermissionStatus
    ) -> PermissionGuidance {
        sourceGuidance(presentation: presentation) { cameraGuidance(status: status) }
    }

    private func sourceGuidance(
        presentation: CaptureSourcePermissionPresentation,
        fallback: () -> PermissionGuidance
    ) -> PermissionGuidance {
        if presentation.phase == .offByUser {
            return PermissionGuidance(
                title: presentation.title,
                message: presentation.message,
                actionTitle: presentation.actionTitle,
                action: .enableSource
            )
        }
        return fallback()
    }

    private func inputMonitoringGuidance(status: PermissionStatus) -> PermissionGuidance {
        switch status {
        case .authorized:
            PermissionGuidance(
                title: "Keystroke capture ready",
                message: "Luxel can capture key identities while an enabled recording is active.",
                actionTitle: "OK",
                action: .request
            )
        case .notDetermined:
            PermissionGuidance(
                title: "Allow keystroke capture?",
                message:
                    "Luxel stores typed characters and shortcut identities locally with the recording. "
                    + "You can pause capture at any time and remove the data later.",
                actionTitle: "Open System Settings",
                action: .request
            )
        case .denied, .restricted, .unknown:
            PermissionGuidance(
                title: "Input Monitoring is off",
                message: "Turn Luxel on in Input Monitoring, then return and try again. "
                    + "If permission is already on but capture remains unavailable, relaunch Luxel.",
                actionTitle: "Open System Settings",
                action: .openSettings
            )
        }
    }
}
