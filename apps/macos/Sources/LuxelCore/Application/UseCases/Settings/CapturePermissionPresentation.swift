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
    public let screenshotAvailable: Bool
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
        screenshotAvailable = hasScreenAccess && hasSelectedCaptureTarget
        systemAudioTrackAvailable = systemAudio.isReady
        microphoneTrackAvailable = microphone.isReady
        audioOnlyRecordingAvailable = systemAudioTrackAvailable || microphoneTrackAvailable
        recordAgainAvailable = hasScreenAccess && hasLastCaptureMemory
        cameraOverlayAvailable = camera.isReady
    }

    public func presentation(for source: CapturePermissionSource) -> CaptureSourcePermissionPresentation {
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

    private static func screenPresentation(
        status: PermissionStatus
    ) -> CaptureSourcePermissionPresentation {
        if status == .authorized {
            return CaptureSourcePermissionPresentation(
                source: .screenPixels,
                phase: .ready,
                title: "Screen capture ready",
                message: "Luxel can record your screen and system sound.",
                actionTitle: "OK",
                systemImage: "display",
                statusTitle: "Ready"
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .screenPixels,
            phase: .needsGrant,
            title: "Screen capture is off",
            message: "macOS needs approval before Luxel can record your screen or system sound. "
                + "If Luxel is not listed, click + and add the app.",
            actionTitle: "Enable Capture",
            systemImage: "display",
            statusTitle: "Required"
        )
    }

    private static func systemAudioPresentation(
        screenRecordingStatus: PermissionStatus,
        recordsSystemAudio: Bool
    ) -> CaptureSourcePermissionPresentation {
        guard screenRecordingStatus == .authorized else {
            return CaptureSourcePermissionPresentation(
                source: .systemAudio,
                phase: .needsGrant,
                title: "System sound is off",
                message: "Turn Luxel on for system audio in Screen & System Audio Recording. "
                    + "If Luxel is not listed, click + and add the app.",
                actionTitle: "Enable System Sound",
                systemImage: "speaker.slash.fill",
                statusTitle: "Required"
            )
        }

        guard recordsSystemAudio else {
            return CaptureSourcePermissionPresentation(
                source: .systemAudio,
                phase: .offByUser,
                title: "System sound is off",
                message: "System sound uses macOS Screen & System Audio Recording. Microphone uses a separate permission.",
                actionTitle: "Enable System Sound",
                systemImage: "speaker.slash.fill",
                statusTitle: "Off"
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .systemAudio,
            phase: .ready,
            title: "System sound on",
            message: "System sound will be included with screen recordings.",
            actionTitle: "Turn Off",
            systemImage: "speaker.wave.2.fill",
            statusTitle: "Ready"
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
                title: "Microphone is off",
                message: "Allow microphone access to add your voice to recordings.",
                actionTitle: "Enable Mic",
                systemImage: "mic.slash",
                statusTitle: "Required"
            )
        }

        guard recordsMicrophone else {
            return CaptureSourcePermissionPresentation(
                source: .microphone,
                phase: .offByUser,
                title: "Microphone is off",
                message: "Enable microphone audio to add your voice to recordings.",
                actionTitle: "Enable Mic",
                systemImage: "mic.slash",
                statusTitle: "Off"
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .microphone,
            phase: .ready,
            title: "Microphone on",
            message: "Microphone audio will be included with recordings.",
            actionTitle: "Turn Off",
            systemImage: "mic.fill",
            statusTitle: "Ready"
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
                title: "Camera is off",
                message: "Allow camera access to add your camera overlay.",
                actionTitle: "Enable Camera",
                systemImage: "video.slash",
                statusTitle: "Required"
            )
        }

        guard hasCameraSelection else {
            return CaptureSourcePermissionPresentation(
                source: .camera,
                phase: .offByUser,
                title: "Camera is off",
                message: "Choose a camera to add your camera overlay.",
                actionTitle: "Choose Camera",
                systemImage: "video.slash",
                statusTitle: "Off"
            )
        }

        return CaptureSourcePermissionPresentation(
            source: .camera,
            phase: .ready,
            title: "Camera on",
            message: "Camera overlay will be included with recordings.",
            actionTitle: "Turn Off",
            systemImage: "video.fill",
            statusTitle: "Ready"
        )
    }
}
