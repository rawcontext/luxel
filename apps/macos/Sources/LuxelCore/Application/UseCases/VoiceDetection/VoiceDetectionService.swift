import Foundation

public actor VoiceDetectionService {
    public struct Configuration: Equatable, Sendable {
        public let entryProbability: Float
        public let sustainedSpeechDuration: TimeInterval
        public let candidateWindowDuration: TimeInterval
        public let rearmSilenceDuration: TimeInterval
        public let promptCooldown: TimeInterval

        public init(
            entryProbability: Float = 0.85,
            sustainedSpeechDuration: TimeInterval = 1,
            candidateWindowDuration: TimeInterval = 1.5,
            rearmSilenceDuration: TimeInterval = 30,
            promptCooldown: TimeInterval = 300
        ) {
            self.entryProbability = entryProbability
            self.sustainedSpeechDuration = sustainedSpeechDuration
            self.candidateWindowDuration = candidateWindowDuration
            self.rearmSilenceDuration = rearmSilenceDuration
            self.promptCooldown = promptCooldown
        }

        public static let `default` = Configuration()
    }

    private struct PositiveFrame: Equatable, Sendable {
        let observedAt: Date
        let duration: TimeInterval
    }

    private enum PolicyState: Equatable, Sendable {
        case off
        case armed
        case candidate
        case prompted(promptedAt: Date, silenceStartedAt: Date?)
    }

    public private(set) var runtimeStatus: VoiceDetectionRuntimeStatus = .off

    private let configuration: Configuration
    private var eligibility: VoiceDetectionEligibility = .disabled
    private var state: PolicyState = .off
    private var positiveFrames: [PositiveFrame] = []
    private var detectorDeviceID: String?
    private var detectorIsRunning = false
    private var hasOutstandingPrompt = false

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func reconcile(
        eligibility nextEligibility: VoiceDetectionEligibility
    ) -> [VoiceDetectionEffect] {
        let previousEligibility = eligibility
        eligibility = nextEligibility
        runtimeStatus = nextEligibility.runtimeStatus

        guard nextEligibility.canRunDetector, let microphone = nextEligibility.microphone else {
            let effects = stopAndResetEffects()
            state = .off
            return effects
        }

        let deviceChanged = previousEligibility.microphone?.deviceID != microphone.deviceID
        if detectorIsRunning, deviceChanged {
            clearPolicyState(armed: true)
            detectorDeviceID = microphone.deviceID
            return promptRemovalEffect() + [
                .stopDetector,
                .resetDetector,
                .startDetector(deviceID: microphone.deviceID)
            ]
        }

        guard !detectorIsRunning else {
            return []
        }

        clearPolicyState(armed: true)
        detectorIsRunning = true
        detectorDeviceID = microphone.deviceID
        return [.resetDetector, .startDetector(deviceID: microphone.deviceID)]
    }

    public func handle(_ event: VoiceActivityDetectorEvent) -> [VoiceDetectionEffect] {
        guard detectorIsRunning, eligibility.canRunDetector else {
            return []
        }

        switch event {
        case .observation(let observation):
            return handle(observation)
        case .reset:
            clearPolicyState(armed: true)
            return promptRemovalEffect() + [.resetDetector]
        case .failed:
            detectorIsRunning = false
            detectorDeviceID = nil
            clearPolicyState(armed: false)
            runtimeStatus = .unavailable
            return promptRemovalEffect() + [.stopDetector]
        }
    }

    public func handlePromptAction(
        _ action: VoiceDetectionPromptAction,
        at date: Date
    ) -> [VoiceDetectionEffect] {
        switch action {
        case .startRecording:
            guard hasOutstandingPrompt,
                  case .prompted = state,
                  eligibility.canRunDetector
            else {
                return [.activateApplication]
            }
            hasOutstandingPrompt = false
            state = .off
            positiveFrames.removeAll(keepingCapacity: false)
            let detectorEffect: [VoiceDetectionEffect] = detectorIsRunning ? [.stopDetector] : []
            detectorIsRunning = false
            detectorDeviceID = nil
            return [.removePrompt] + detectorEffect + [.startRecording]
        case .dismiss:
            hasOutstandingPrompt = false
            if case .prompted(let promptedAt, _) = state {
                state = .prompted(promptedAt: promptedAt, silenceStartedAt: date)
            }
            return [.removePrompt]
        case .defaultAction:
            return [.activateApplication]
        }
    }

    public func reset(for reason: VoiceDetectionResetReason) -> [VoiceDetectionEffect] {
        clearPolicyState(armed: eligibility.canRunDetector)
        let shouldStop = switch reason {
        case .deviceChanged, .displaySleep, .sessionLocked, .permissionChanged,
             .recordingChanged, .disabled, .detectorStopped:
            true
        case .discontinuity, .queueOverflow:
            false
        }

        if shouldStop {
            detectorIsRunning = false
            detectorDeviceID = nil
        }

        return promptRemovalEffect() + (shouldStop ? [.stopDetector] : [.resetDetector])
    }

    private func handle(_ observation: VoiceActivityObservation) -> [VoiceDetectionEffect] {
        let isPositive = observation.probability >= configuration.entryProbability
            || observation.kind == .speechStarted

        if case .prompted = state {
            return updatePromptedState(isPositive: isPositive, at: observation.observedAt)
        }

        guard isPositive else {
            prunePositiveFrames(at: observation.observedAt)
            state = positiveFrames.isEmpty ? .armed : .candidate
            return []
        }

        positiveFrames.append(
            PositiveFrame(observedAt: observation.observedAt, duration: observation.frameDuration)
        )
        prunePositiveFrames(at: observation.observedAt)
        state = .candidate

        let positiveDuration = positiveFrames.reduce(0) { $0 + $1.duration }
        guard positiveDuration >= configuration.sustainedSpeechDuration else {
            return []
        }

        positiveFrames.removeAll(keepingCapacity: false)
        state = .prompted(promptedAt: observation.observedAt, silenceStartedAt: nil)
        hasOutstandingPrompt = true
        return [.postPrompt]
    }

    private func updatePromptedState(isPositive: Bool, at date: Date) -> [VoiceDetectionEffect] {
        guard case .prompted(let promptedAt, let silenceStartedAt) = state else {
            return []
        }

        if isPositive {
            state = .prompted(promptedAt: promptedAt, silenceStartedAt: nil)
            return []
        }

        let silenceStart = silenceStartedAt ?? date
        state = .prompted(promptedAt: promptedAt, silenceStartedAt: silenceStart)
        guard date.timeIntervalSince(promptedAt) >= configuration.promptCooldown,
              date.timeIntervalSince(silenceStart) >= configuration.rearmSilenceDuration
        else {
            return []
        }

        state = .armed
        let effects = promptRemovalEffect()
        hasOutstandingPrompt = false
        return effects
    }

    private func prunePositiveFrames(at date: Date) {
        let cutoff = date.addingTimeInterval(-configuration.candidateWindowDuration)
        positiveFrames.removeAll { $0.observedAt < cutoff }
    }

    private func stopAndResetEffects() -> [VoiceDetectionEffect] {
        let effects = promptRemovalEffect() + (detectorIsRunning ? [.stopDetector] : [])
        detectorIsRunning = false
        detectorDeviceID = nil
        clearPolicyState(armed: false)
        return effects
    }

    private func promptRemovalEffect() -> [VoiceDetectionEffect] {
        guard hasOutstandingPrompt else {
            return []
        }
        hasOutstandingPrompt = false
        return [.removePrompt]
    }

    private func clearPolicyState(armed: Bool) {
        positiveFrames.removeAll(keepingCapacity: false)
        state = armed ? .armed : .off
    }
}
