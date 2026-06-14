import Foundation

public final class ReplayBufferService: @unchecked Sendable {
    private let engine: any ReplayBufferEngine
    private let state = ReplayBufferServiceState()

    public init(engine: any ReplayBufferEngine) {
        self.engine = engine
    }

    public var replayBufferState: AsyncStream<ReplayBufferState> {
        engine.state
    }

    public func arm(configuration: ReplayBufferConfiguration) async throws {
        try await engine.arm(configuration: configuration)
        state.arm(configuration: configuration)
    }

    public func disarm() async throws {
        try await engine.disarm()
        state.disarm()
    }

    public func pauseByUser() async throws {
        try await setPauseReason(.user, isActive: true, requiresArmedBuffer: true)
    }

    public func resumeByUser() async throws {
        try await setPauseReason(.user, isActive: false, requiresArmedBuffer: true)
    }

    public func recordingDidStart() async throws {
        try await setPauseReason(.recordingActive, isActive: true)
    }

    public func recordingDidStop() async throws {
        try await setPauseReason(.recordingActive, isActive: false)
    }

    public func pauseForSystemReason(_ reason: ReplayBufferPauseReason) async throws {
        try await setPauseReason(reason, isActive: true)
    }

    public func resumeSystemReason(_ reason: ReplayBufferPauseReason) async throws {
        try await setPauseReason(reason, isActive: false)
    }

    public func clip(lastSeconds: TimeInterval? = nil) async throws -> URL {
        guard let configuration = state.configuration() else {
            throw ReplayBufferServiceError.notArmed
        }

        let seconds = lastSeconds ?? configuration.bufferLength
        guard seconds.isFinite, seconds > 0 else {
            throw ReplayBufferModelError.invalidClipDuration
        }

        return try await engine.clip(lastSeconds: seconds)
    }

    private func setPauseReason(
        _ reason: ReplayBufferPauseReason,
        isActive: Bool,
        requiresArmedBuffer: Bool = false
    ) async throws {
        guard state.isArmed else {
            if requiresArmedBuffer {
                throw ReplayBufferServiceError.notArmed
            }
            return
        }

        let transition = state.previewSetting(reason, isActive: isActive)
        guard transition.previousActiveReason != transition.nextActiveReason else {
            state.commit(transition)
            return
        }

        do {
            if let nextActiveReason = transition.nextActiveReason {
                try await engine.pause(reason: nextActiveReason)
            } else {
                try await engine.resume()
            }
            state.commit(transition)
        } catch {
            throw error
        }
    }
}

public enum ReplayBufferServiceError: Error, Equatable {
    case notArmed
}

private struct ReplayBufferPauseTransition {
    let previousReasons: Set<ReplayBufferPauseReason>
    let nextReasons: Set<ReplayBufferPauseReason>
    let previousActiveReason: ReplayBufferPauseReason?
    let nextActiveReason: ReplayBufferPauseReason?
}

private final class ReplayBufferServiceState: @unchecked Sendable {
    private let lock = NSLock()
    private var currentConfiguration: ReplayBufferConfiguration?
    private var pauseReasons: Set<ReplayBufferPauseReason> = []

    var isArmed: Bool {
        lock.withLock {
            currentConfiguration != nil
        }
    }

    func configuration() -> ReplayBufferConfiguration? {
        lock.withLock {
            currentConfiguration
        }
    }

    func arm(configuration: ReplayBufferConfiguration) {
        lock.withLock {
            currentConfiguration = configuration
            pauseReasons = []
        }
    }

    func disarm() {
        lock.withLock {
            currentConfiguration = nil
            pauseReasons = []
        }
    }

    func previewSetting(
        _ reason: ReplayBufferPauseReason,
        isActive: Bool
    ) -> ReplayBufferPauseTransition {
        lock.withLock {
            var nextReasons = pauseReasons
            if isActive {
                nextReasons.insert(reason)
            } else {
                nextReasons.remove(reason)
            }

            return ReplayBufferPauseTransition(
                previousReasons: pauseReasons,
                nextReasons: nextReasons,
                previousActiveReason: activeReason(in: pauseReasons),
                nextActiveReason: activeReason(in: nextReasons)
            )
        }
    }

    func commit(_ transition: ReplayBufferPauseTransition) {
        lock.withLock {
            guard pauseReasons == transition.previousReasons else {
                return
            }

            pauseReasons = transition.nextReasons
        }
    }

    private func activeReason(
        in reasons: Set<ReplayBufferPauseReason>
    ) -> ReplayBufferPauseReason? {
        for reason in [
            ReplayBufferPauseReason.user,
            .recordingActive,
            .locked,
            .displaySleep,
            .battery,
            .displayChanged
        ] where reasons.contains(reason) {
            return reason
        }

        return nil
    }
}
