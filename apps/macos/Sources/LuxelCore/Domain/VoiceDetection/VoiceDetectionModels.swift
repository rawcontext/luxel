import Foundation

public enum VoiceDetectionAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public struct VoiceDetectionMicrophone: Equatable, Sendable {
    public let deviceID: String?
    public let name: String

    public init(deviceID: String?, name: String) {
        self.deviceID = deviceID
        self.name = name
    }
}

public struct VoiceDetectionEligibility: Equatable, Sendable {
    public let isEnabled: Bool
    public let isDisclosureAccepted: Bool
    public let notificationPermission: VoiceDetectionAuthorizationStatus
    public let microphonePermission: VoiceDetectionAuthorizationStatus
    public let microphone: VoiceDetectionMicrophone?
    public let isModelAvailable: Bool
    public let isDetectorReady: Bool
    public let isRecordingLifecycleIdle: Bool
    public let isSessionLocked: Bool
    public let isDisplayAsleep: Bool

    public init(
        isEnabled: Bool,
        isDisclosureAccepted: Bool,
        notificationPermission: VoiceDetectionAuthorizationStatus,
        microphonePermission: VoiceDetectionAuthorizationStatus,
        microphone: VoiceDetectionMicrophone?,
        isModelAvailable: Bool,
        isDetectorReady: Bool,
        isRecordingLifecycleIdle: Bool,
        isSessionLocked: Bool,
        isDisplayAsleep: Bool
    ) {
        self.isEnabled = isEnabled
        self.isDisclosureAccepted = isDisclosureAccepted
        self.notificationPermission = notificationPermission
        self.microphonePermission = microphonePermission
        self.microphone = microphone
        self.isModelAvailable = isModelAvailable
        self.isDetectorReady = isDetectorReady
        self.isRecordingLifecycleIdle = isRecordingLifecycleIdle
        self.isSessionLocked = isSessionLocked
        self.isDisplayAsleep = isDisplayAsleep
    }

    public static let disabled = VoiceDetectionEligibility(
        isEnabled: false,
        isDisclosureAccepted: false,
        notificationPermission: .notDetermined,
        microphonePermission: .notDetermined,
        microphone: nil,
        isModelAvailable: false,
        isDetectorReady: false,
        isRecordingLifecycleIdle: true,
        isSessionLocked: false,
        isDisplayAsleep: false
    )

    public var runtimeStatus: VoiceDetectionRuntimeStatus {
        guard isEnabled, isDisclosureAccepted else {
            return .off
        }
        guard isRecordingLifecycleIdle else {
            return .pausedWhileRecording
        }
        guard !isSessionLocked, !isDisplayAsleep else {
            return .pausedWhileLocked
        }
        guard microphonePermission == .authorized else {
            return .microphoneAccessRequired
        }
        guard notificationPermission == .authorized else {
            return .notificationsRequired
        }
        guard let microphone else {
            return .selectedMicrophoneUnavailable
        }
        guard isModelAvailable else {
            return .unavailable
        }
        guard isDetectorReady else {
            return .preparing
        }
        return .listening(microphoneName: microphone.name)
    }

    public var canRunDetector: Bool {
        switch runtimeStatus {
        case .preparing, .listening:
            true
        case .off, .pausedWhileRecording, .pausedWhileLocked, .microphoneAccessRequired,
            .notificationsRequired, .selectedMicrophoneUnavailable, .unavailable:
            false
        }
    }
}

public enum VoiceDetectionRuntimeStatus: Equatable, Sendable {
    case off
    case preparing
    case listening(microphoneName: String)
    case pausedWhileRecording
    case pausedWhileLocked
    case microphoneAccessRequired
    case notificationsRequired
    case selectedMicrophoneUnavailable
    case unavailable
}

public enum VoiceActivityObservationKind: Equatable, Sendable {
    case probability
    case speechStarted
    case speechEnded
}

public struct VoiceActivityObservation: Equatable, Sendable {
    public let probability: Float
    public let frameDuration: TimeInterval
    public let observedAt: Date
    public let kind: VoiceActivityObservationKind

    public init(
        probability: Float,
        frameDuration: TimeInterval = 0.256,
        observedAt: Date,
        kind: VoiceActivityObservationKind = .probability
    ) {
        self.probability = probability
        self.frameDuration = frameDuration
        self.observedAt = observedAt
        self.kind = kind
    }
}

public enum VoiceActivityDetectionFailure: Error, Equatable, Sendable {
    case selectedDeviceUnavailable
    case modelUnavailable
    case captureUnavailable
    case conversionFailed
    case inferenceFailed
}

public enum VoiceActivityDetectorEvent: Equatable, Sendable {
    case observation(VoiceActivityObservation)
    case reset(VoiceDetectionResetReason)
    case failed(VoiceActivityDetectionFailure)
}

public enum VoiceDetectionResetReason: Equatable, Sendable {
    case disabled
    case deviceChanged
    case discontinuity
    case queueOverflow
    case displaySleep
    case sessionLocked
    case permissionChanged
    case recordingChanged
    case detectorStopped
}

public enum VoiceDetectionPromptAction: Equatable, Sendable {
    case startRecording
    case dismiss
    case defaultAction
}

public enum VoiceDetectionEffect: Equatable, Sendable {
    case startDetector(deviceID: String?)
    case stopDetector
    case resetDetector
    case postPrompt
    case removePrompt
    case startRecording
    case activateApplication
}
