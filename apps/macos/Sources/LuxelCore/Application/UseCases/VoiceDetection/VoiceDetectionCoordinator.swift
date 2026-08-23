import Foundation

public enum VoiceDetectionCoordinatorOutcome: Equatable, Sendable {
    case none
    case startRecording
    case activateApplication
}

public actor VoiceDetectionCoordinator {
    public nonisolated let statusUpdates: AsyncStream<VoiceDetectionRuntimeStatus>

    private let service: VoiceDetectionService
    private let detector: any VoiceActivityDetecting
    private let notifier: any VoiceRecordingPromptNotifying
    private let statusContinuation: AsyncStream<VoiceDetectionRuntimeStatus>.Continuation
    private var detectorEventsTask: Task<Void, Never>?
    private var detectorIsRunning = false

    public init(
        service: VoiceDetectionService = VoiceDetectionService(),
        detector: any VoiceActivityDetecting,
        notifier: any VoiceRecordingPromptNotifying
    ) {
        self.service = service
        self.detector = detector
        self.notifier = notifier
        let statuses = AsyncStream.makeStream(
            of: VoiceDetectionRuntimeStatus.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        statusUpdates = statuses.stream
        statusContinuation = statuses.continuation
        statuses.continuation.yield(.off)
    }

    public func notificationAuthorizationStatus() async -> VoiceDetectionAuthorizationStatus {
        await notifier.authorizationStatus()
    }

    public func requestNotificationAuthorization() async -> VoiceDetectionAuthorizationStatus {
        await notifier.requestAuthorization()
    }

    public func recoverNotificationAuthorization() async -> VoiceDetectionAuthorizationStatus {
        let status = await notifier.authorizationStatus()
        if status == .notDetermined {
            return await notifier.requestAuthorization()
        }
        if status == .denied {
            await notifier.openSettings()
        }
        return status
    }

    @discardableResult
    public func reconcile(
        eligibility: VoiceDetectionEligibility
    ) async -> VoiceDetectionRuntimeStatus {
        let effects = await service.reconcile(eligibility: eligibility)
        _ = await execute(effects)
        return await publishRuntimeStatus()
    }

    public func handlePromptAction(
        _ action: VoiceDetectionPromptAction,
        at date: Date = Date()
    ) async -> VoiceDetectionCoordinatorOutcome {
        let effects = await service.handlePromptAction(action, at: date)
        let outcome = await execute(effects)
        _ = await publishRuntimeStatus()
        return outcome
    }

    public func shutdown() async {
        let effects = await service.reset(for: .disabled)
        _ = await execute(effects)
        await stopDetector()
        await notifier.removePrompt()
        statusContinuation.yield(.off)
    }

    func receive(_ event: VoiceActivityDetectorEvent) async {
        let effects = await service.handle(event)
        _ = await execute(effects)
        _ = await publishRuntimeStatus()
    }

    private func execute(
        _ effects: [VoiceDetectionEffect]
    ) async -> VoiceDetectionCoordinatorOutcome {
        var outcome = VoiceDetectionCoordinatorOutcome.none
        for effect in effects {
            switch effect {
            case .startDetector(let deviceID):
                await startDetector(deviceID: deviceID)
            case .stopDetector:
                await stopDetector()
            case .resetDetector:
                break
            case .postPrompt:
                try? await notifier.postPrompt()
            case .removePrompt:
                await notifier.removePrompt()
            case .startRecording:
                outcome = .startRecording
            case .activateApplication:
                outcome = .activateApplication
            }
        }
        return outcome
    }

    private func startDetector(deviceID: String?) async {
        if detectorIsRunning {
            await stopDetector()
        }
        let events = await detector.start(deviceID: deviceID)
        detectorIsRunning = true
        detectorEventsTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    break
                }
                await self?.receive(event)
            }
        }
    }

    private func stopDetector() async {
        guard detectorIsRunning || detectorEventsTask != nil else {
            return
        }
        let task = detectorEventsTask
        detectorEventsTask = nil
        detectorIsRunning = false
        task?.cancel()
        await detector.stop()
        await task?.value
    }

    private func publishRuntimeStatus() async -> VoiceDetectionRuntimeStatus {
        let status = await service.runtimeStatus
        statusContinuation.yield(status)
        return status
    }
}
