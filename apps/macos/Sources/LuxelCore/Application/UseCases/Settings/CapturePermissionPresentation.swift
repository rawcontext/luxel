public enum CapturePermissionSource: String, Codable, CaseIterable, Equatable, Sendable {
    case screenPixels
    case systemAudio
    case microphone
    case camera

    public var systemPermission: SystemPermission {
        switch self {
        case .screenPixels, .systemAudio:
            .screenRecording
        case .microphone:
            .microphone
        case .camera:
            .camera
        }
    }
}

public enum CaptureSourcePermissionPhase: String, Codable, Equatable, Sendable {
    case checking
    case offByUser
    case needsGrant
    case requestInProgress
    case openSettings
    case grantedNeedsRelaunch
    case ready
    case pausedByMacOS
    case blocked
}

public struct CaptureSourcePermissionPresentation: Equatable, Sendable {
    public let source: CapturePermissionSource
    public let phase: CaptureSourcePermissionPhase
    public let title: String
    public let message: String
    public let actionTitle: String
    public let systemImage: String
    public let statusTitle: String

    public init(
        source: CapturePermissionSource,
        phase: CaptureSourcePermissionPhase,
        title: String,
        message: String,
        actionTitle: String,
        systemImage: String,
        statusTitle: String
    ) {
        self.source = source
        self.phase = phase
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.systemImage = systemImage
        self.statusTitle = statusTitle
    }

    public var isReady: Bool {
        phase == .ready
    }

    public var needsSetup: Bool {
        switch phase {
        case .needsGrant, .openSettings, .grantedNeedsRelaunch, .pausedByMacOS, .blocked:
            true
        case .checking, .offByUser, .requestInProgress, .ready:
            false
        }
    }
}

public struct CaptureCapabilityState: Equatable, Sendable {
    public let screen: CaptureSourcePermissionPresentation
    public let systemAudio: CaptureSourcePermissionPresentation
    public let microphone: CaptureSourcePermissionPresentation
    public let camera: CaptureSourcePermissionPresentation
    public let screenRecordingAvailable: Bool
    public let areaRecordingAvailable: Bool
    public let audioOnlyRecordingAvailable: Bool
    public let recordAgainAvailable: Bool
    public let systemAudioTrackAvailable: Bool
    public let microphoneTrackAvailable: Bool
    public let cameraOverlayAvailable: Bool

    public init(
        screenRecordingStatus: PermissionStatus,
        microphoneStatus: PermissionStatus,
        cameraStatus: PermissionStatus,
        recordsSystemAudio: Bool,
        recordsMicrophone: Bool,
        hasCameraSelection: Bool,
        hasSelectedCaptureTarget: Bool = false,
        hasLastCaptureMemory: Bool = false
    ) {
        screen = Self.screenPresentation(status: screenRecordingStatus)
        systemAudio = Self.systemAudioPresentation(
            screenRecordingStatus: screenRecordingStatus,
            recordsSystemAudio: recordsSystemAudio
        )
        microphone = Self.microphonePresentation(
            status: microphoneStatus,
            recordsMicrophone: recordsMicrophone
        )
        camera = Self.cameraPresentation(
            status: cameraStatus,
            hasCameraSelection: hasCameraSelection
        )

        let hasScreenAccess = screen.isReady
        screenRecordingAvailable = hasScreenAccess && hasSelectedCaptureTarget
        areaRecordingAvailable = hasScreenAccess
        systemAudioTrackAvailable = systemAudio.isReady
        microphoneTrackAvailable = microphone.isReady
        audioOnlyRecordingAvailable = systemAudioTrackAvailable || microphoneTrackAvailable
        recordAgainAvailable = hasScreenAccess && hasLastCaptureMemory
        cameraOverlayAvailable = camera.isReady
    }

    public func presentation(for source: CapturePermissionSource)
        -> CaptureSourcePermissionPresentation {
        switch source {
        case .screenPixels:
            screen
        case .systemAudio:
            systemAudio
        case .microphone:
            microphone
        case .camera:
            camera
        }
    }
}

extension CaptureCapabilityState {
    private static func screenPresentation(
        status: PermissionStatus
    ) -> CaptureSourcePermissionPresentation {
        if status == .authorized {
            return CaptureSourcePermissionPresentation(
                source: .screenPixels,
                phase: .ready,
                title: LuxelLocalization.string(
                    "permissions.screen.ready.title",
                    defaultValue: "Screen capture ready"),
                message: LuxelLocalization.string(
                    "permissions.screen.ready.message",
                    defaultValue: "Luxel can record your screen and system sound."),
                actionTitle: LuxelLocalization.string("common.ok", defaultValue: "OK"),
                systemImage: "display",
                statusTitle: LuxelLocalization.string("status.ready", defaultValue: "Ready")
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .screenPixels,
            phase: .needsGrant,
            title: LuxelLocalization.string(
                "permissions.screen.off.title",
                defaultValue: "Screen capture is off"),
            message: LuxelLocalization.string(
                "permissions.screen.off.message",
                defaultValue:
                    "macOS needs approval before Luxel can record your screen or system sound. "
                    + "If Luxel is not listed, click + and add the app."
            ),
            actionTitle: LuxelLocalization.string(
                "permissions.screen.enable",
                defaultValue: "Enable Capture"),
            systemImage: "display",
            statusTitle: LuxelLocalization.string("status.required", defaultValue: "Required")
        )
    }

    private static func systemAudioPresentation(
        screenRecordingStatus: PermissionStatus,
        recordsSystemAudio: Bool
    ) -> CaptureSourcePermissionPresentation {
        guard screenRecordingStatus == .authorized else {
            return systemAudioGrantPresentation()
        }

        guard recordsSystemAudio else {
            return CaptureSourcePermissionPresentation(
                source: .systemAudio,
                phase: .offByUser,
                title: LuxelLocalization.string(
                    "permissions.systemAudio.off.title",
                    defaultValue: "System sound is off"),
                message: LuxelLocalization.string(
                    "permissions.systemAudio.off.message",
                    defaultValue:
                        "System sound uses macOS Screen & System Audio Recording. "
                        + "Microphone uses a separate permission."
                ),
                actionTitle: LuxelLocalization.string(
                    "permissions.systemAudio.enable",
                    defaultValue: "Enable System Sound"),
                systemImage: "speaker.slash.fill",
                statusTitle: LuxelLocalization.string("status.off", defaultValue: "Off")
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .systemAudio,
            phase: .ready,
            title: LuxelLocalization.string(
                "permissions.systemAudio.ready.title",
                defaultValue: "System sound on"),
            message: LuxelLocalization.string(
                "permissions.systemAudio.ready.message",
                defaultValue: "System sound will be included with screen recordings."),
            actionTitle: LuxelLocalization.string("common.turnOff", defaultValue: "Turn Off"),
            systemImage: "speaker.wave.2.fill",
            statusTitle: LuxelLocalization.string("status.ready", defaultValue: "Ready")
        )
    }

    fileprivate static func systemAudioGrantPresentation() -> CaptureSourcePermissionPresentation {
        CaptureSourcePermissionPresentation(
            source: .systemAudio,
            phase: .needsGrant,
            title: LuxelLocalization.string(
                "permissions.systemAudio.off.title",
                defaultValue: "System sound is off"
            ),
            message: LuxelLocalization.string(
                "permissions.systemAudio.grant.message",
                defaultValue:
                    "Turn Luxel on for system audio in Screen & System Audio Recording. "
                    + "If Luxel is not listed, click + and add the app."
            ),
            actionTitle: LuxelLocalization.string(
                "permissions.systemAudio.enable",
                defaultValue: "Enable System Sound"
            ),
            systemImage: "speaker.slash.fill",
            statusTitle: LuxelLocalization.string("status.required", defaultValue: "Required")
        )
    }

    private static func microphonePresentation(
        status: PermissionStatus,
        recordsMicrophone: Bool
    ) -> CaptureSourcePermissionPresentation {
        guard status == .authorized else {
            return CaptureSourcePermissionPresentation(
                source: .microphone,
                phase: .needsGrant,
                title: LuxelLocalization.string(
                    "permissions.microphone.off.title",
                    defaultValue: "Microphone is off"),
                message: LuxelLocalization.string(
                    "permissions.microphone.grant.message",
                    defaultValue: "Allow microphone access to add your voice to recordings."),
                actionTitle: LuxelLocalization.string(
                    "permissions.microphone.enable",
                    defaultValue: "Enable Mic"),
                systemImage: "mic.slash",
                statusTitle: LuxelLocalization.string("status.required", defaultValue: "Required")
            )
        }

        guard recordsMicrophone else {
            return CaptureSourcePermissionPresentation(
                source: .microphone,
                phase: .offByUser,
                title: LuxelLocalization.string(
                    "permissions.microphone.off.title",
                    defaultValue: "Microphone is off"),
                message: LuxelLocalization.string(
                    "permissions.microphone.off.message",
                    defaultValue: "Enable microphone audio to add your voice to recordings."),
                actionTitle: LuxelLocalization.string(
                    "permissions.microphone.enable",
                    defaultValue: "Enable Mic"),
                systemImage: "mic.slash",
                statusTitle: LuxelLocalization.string("status.off", defaultValue: "Off")
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .microphone,
            phase: .ready,
            title: LuxelLocalization.string(
                "permissions.microphone.ready.title",
                defaultValue: "Microphone on"),
            message: LuxelLocalization.string(
                "permissions.microphone.ready.message",
                defaultValue: "Microphone audio will be included with recordings."),
            actionTitle: LuxelLocalization.string("common.turnOff", defaultValue: "Turn Off"),
            systemImage: "mic.fill",
            statusTitle: LuxelLocalization.string("status.ready", defaultValue: "Ready")
        )
    }

    private static func cameraPresentation(
        status: PermissionStatus,
        hasCameraSelection: Bool
    ) -> CaptureSourcePermissionPresentation {
        guard status == .authorized else {
            return CaptureSourcePermissionPresentation(
                source: .camera,
                phase: .needsGrant,
                title: LuxelLocalization.string(
                    "permissions.camera.off.title",
                    defaultValue: "Camera is off"),
                message: LuxelLocalization.string(
                    "permissions.camera.grant.message",
                    defaultValue: "Allow camera access to add your camera overlay."),
                actionTitle: LuxelLocalization.string(
                    "permissions.camera.enable",
                    defaultValue: "Enable Camera"),
                systemImage: "video.slash",
                statusTitle: LuxelLocalization.string("status.required", defaultValue: "Required")
            )
        }

        guard hasCameraSelection else {
            return CaptureSourcePermissionPresentation(
                source: .camera,
                phase: .offByUser,
                title: LuxelLocalization.string(
                    "permissions.camera.off.title",
                    defaultValue: "Camera is off"),
                message: LuxelLocalization.string(
                    "permissions.camera.off.message",
                    defaultValue: "Choose a camera to add your camera overlay."),
                actionTitle: LuxelLocalization.string(
                    "permissions.camera.choose",
                    defaultValue: "Choose Camera"),
                systemImage: "video.slash",
                statusTitle: LuxelLocalization.string("status.off", defaultValue: "Off")
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .camera,
            phase: .ready,
            title: LuxelLocalization.string(
                "permissions.camera.ready.title",
                defaultValue: "Camera on"),
            message: LuxelLocalization.string(
                "permissions.camera.ready.message",
                defaultValue: "Camera overlay will be included with recordings."),
            actionTitle: LuxelLocalization.string("common.turnOff", defaultValue: "Turn Off"),
            systemImage: "video.fill",
            statusTitle: LuxelLocalization.string("status.ready", defaultValue: "Ready")
        )
    }
}
