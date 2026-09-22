import Foundation

public final class RecordingLifecycleService: Sendable {
    private let recorder: any CaptureRecorder
    private let history: RecordingHistoryService
    private let dateProvider: any DateProvider
    private let autoStopScheduler: any RecordingAutoStopScheduler
    private let countdownSleeper: any RecordingCountdownSleeper
    private let userNotifier: (any UserNotifier)?
    private let outputFinalizer: any RecordingOutputFinalizer
    private let replayBufferService: ReplayBufferService?
    private let terminationProtection: any RecordingTerminationProtection
    private let autoStopState = RecordingLifecycleAutoStopState()
    private let autoStopEvents = RecordingLifecycleAutoStopEvents()
    private let outputState = RecordingLifecycleOutputState()

    public init(
        recorder: any CaptureRecorder,
        history: RecordingHistoryService,
        dateProvider: any DateProvider = SystemDateProvider(),
        autoStopScheduler: any RecordingAutoStopScheduler = TaskRecordingAutoStopScheduler(),
        countdownSleeper: any RecordingCountdownSleeper = TaskRecordingCountdownSleeper(),
        userNotifier: (any UserNotifier)? = nil,
        outputFinalizer: any RecordingOutputFinalizer = PassthroughRecordingOutputFinalizer(),
        replayBufferService: ReplayBufferService? = nil,
        terminationProtection: any RecordingTerminationProtection =
            NoopRecordingTerminationProtection()
    ) {
        self.recorder = recorder
        self.history = history
        self.dateProvider = dateProvider
        self.autoStopScheduler = autoStopScheduler
        self.countdownSleeper = countdownSleeper
        self.userNotifier = userNotifier
        self.outputFinalizer = outputFinalizer
        self.replayBufferService = replayBufferService
        self.terminationProtection = terminationProtection
    }

    public var autoStopResults: AsyncStream<RecordingAutoStopResult> {
        autoStopEvents.stream()
    }

    @discardableResult
    public func startRecording(
        _ request: RecordingRequest,
        name: String? = nil,
        outputPlan: RecordingOutputFinalizationPlan? = nil
    ) async throws -> ActiveRecording {
        let outputPlan = outputPlan ?? .direct(request.outputFileURL)
        await outputState.set(outputPlan)

        do {
            try await runCountdownIfNeeded(request.schedule)
        } catch {
            await outputState.clear()
            throw error
        }

        terminationProtection.recordingWillStart()
        let activeRecording = history.setCurrentRecording(
            fileURL: outputPlan.stagingFileURL,
            name: name,
            options: request.recordingOptions
        )
        let recorderRequest = request.replacingOutputFileURL(outputPlan.stagingFileURL)

        do {
            try await replayBufferService?.recordingDidStart()
            try await runRecorderOperation { recorder in
                try await recorder.startRecording(recorderRequest)
            }
            await startAutoStopIfNeeded(schedule: request.schedule, startedAt: activeRecording.date)
            return activeRecording.replacingFileURL(outputPlan.finalFileURL)
        } catch {
            try? await replayBufferService?.recordingDidStop()
            await autoStopState.clear()
            await outputState.clear()
            history.clearCurrentRecording()
            terminationProtection.recordingDidEnd()
            throw error
        }
    }

    public func pauseRecording() async throws {
        guard history.getCurrentRecording() != nil else {
            throw RecordingLifecycleError.noActiveRecording
        }

        try await runRecorderOperation { recorder in
            try await recorder.pauseRecording()
        }
        await autoStopState.pause(at: dateProvider.now())
    }

    public func resumeRecording() async throws {
        guard history.getCurrentRecording() != nil else {
            throw RecordingLifecycleError.noActiveRecording
        }

        try await runRecorderOperation { recorder in
            try await recorder.resumeRecording()
        }
        await rescheduleAutoStopIfNeeded(await autoStopState.resume(at: dateProvider.now()))
    }

    @discardableResult
    public func stopRecording(recordingName: String? = nil) async throws -> PastRecording {
        guard await autoStopState.beginStop() else {
            throw RecordingLifecycleError.stopAlreadyInProgress
        }

        do {
            try await runRecorderOperation { recorder in
                try await recorder.stopRecording()
            }
            try? await replayBufferService?.recordingDidStop()
        } catch {
            if let failure = error as? RecordingStopFailure, failure.isTerminal {
                try? await replayBufferService?.recordingDidStop()
                await clearStoppedRecordingState()
            } else {
                await finishStop(succeeded: false)
            }
            throw error
        }

        let finalizationResult: RecordingOutputFinalizationResult?
        do {
            finalizationResult = try await finalizeRecordingOutput(
                await outputState.plan,
                using: outputFinalizer
            )
        } catch {
            await clearStoppedRecordingState()
            throw RecordingLifecycleError.outputFinalizationFailed(error.preferredLocalizedDescription)
        }

        guard
            let recording = history.stopCurrentRecording(
                finalFileURL: finalizationResult?.fileURL,
                recordingName: recordingName
            )
        else {
            await clearStoppedRecordingState()
            throw RecordingLifecycleError.noActiveRecording
        }

        await autoStopState.clear()
        await outputState.clear()
        terminationProtection.recordingDidEnd()
        return recording
    }

    private func startAutoStopIfNeeded(schedule: RecordingSchedule?, startedAt: Date) async {
        guard let schedule else {
            await autoStopState.clear()
            return
        }

        await rescheduleAutoStopIfNeeded(
            await autoStopState.start(schedule: schedule, startedAt: startedAt, now: dateProvider.now())
        )
    }

    private func finishStop(succeeded: Bool) async {
        await rescheduleAutoStopIfNeeded(
            await autoStopState.finishStop(succeeded: succeeded, now: dateProvider.now())
        )
    }

    private func rescheduleAutoStopIfNeeded(_ timing: RecordingLifecycleAutoStopTiming?) async {
        guard let timing else {
            return
        }

        let task = autoStopScheduler.schedule(after: timing.remaining) { [weak self] in
            guard let self, let fileURL = await self.outputState.plan?.finalFileURL else {
                return
            }

            do {
                let recording = try await self.stopRecording()
                self.autoStopEvents.yield(RecordingAutoStopResult(fileURL: fileURL, result: .success(recording)))
                try? await self.userNotifier?.notifyRecordingAutoStopped(duration: timing.maxRecordedDuration)
            } catch {
                self.autoStopEvents.yield(RecordingAutoStopResult(fileURL: fileURL, result: .failure(error)))
            }
        }
        await autoStopState.setTask(task)
    }

    private func runCountdownIfNeeded(_ schedule: RecordingSchedule?) async throws {
        guard let countdown = schedule?.countdown,
            countdown > 0
        else {
            return
        }

        try await countdownSleeper.sleep(for: countdown)
    }

    private func runRecorderOperation(
        _ operation: @escaping @Sendable (any CaptureRecorder) async throws -> Void
    ) async throws {
        let recorder = recorder
        try await Task.detached(priority: .userInitiated) {
            try await operation(recorder)
        }.value
    }

    private func clearStoppedRecordingState() async {
        history.clearCurrentRecording()
        await autoStopState.clear()
        await outputState.clear()
        terminationProtection.recordingDidEnd()
    }
}

public enum RecordingLifecycleError: Error, Equatable, Sendable {
    case noActiveRecording
    case stopAlreadyInProgress
    case outputFinalizationFailed(String)
}

extension RecordingLifecycleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noActiveRecording:
            "No active recording"
        case .stopAlreadyInProgress:
            "Recording stop is already in progress"
        case .outputFinalizationFailed(let message):
            message
        }
    }
}

private struct RecordingLifecycleAutoStopTiming: Sendable {
    let remaining: TimeInterval
    let maxRecordedDuration: TimeInterval
}

private final class RecordingLifecycleAutoStopEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<RecordingAutoStopResult>.Continuation] = [:]

    func stream() -> AsyncStream<RecordingAutoStopResult> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    func yield(_ result: RecordingAutoStopResult) {
        let continuations = lock.withLock {
            Array(self.continuations.values)
        }

        for continuation in continuations {
            continuation.yield(result)
        }
    }

    private func removeContinuation(id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }
}

private actor RecordingLifecycleAutoStopState {
    private var schedule: RecordingSchedule?
    private var clock: RecordingClock?
    private var task: (any RecordingAutoStopTask)?
    private var isStopping = false

    func start(schedule: RecordingSchedule, startedAt: Date, now: Date)
        -> RecordingLifecycleAutoStopTiming? {
        clearStoredState()

        guard schedule.maxRecordedDuration != nil else {
            return nil
        }

        self.schedule = schedule
        clock = RecordingClock(startedAt: startedAt)
        return timing(at: now)
    }

    func pause(at now: Date) {
        guard let currentClock = clock, !isStopping else {
            return
        }

        task?.cancel()
        task = nil
        clock = RecordingClock(
            startedAt: currentClock.startedAt,
            events: currentClock.events + [.pause(at: now)]
        )
    }

    func resume(at now: Date) -> RecordingLifecycleAutoStopTiming? {
        guard let currentClock = clock, !isStopping else {
            return nil
        }

        clock = RecordingClock(
            startedAt: currentClock.startedAt,
            events: currentClock.events + [.resume(at: now)]
        )
        return timing(at: now)
    }

    func setTask(_ task: any RecordingAutoStopTask) {
        guard !isStopping, schedule != nil, clock != nil else {
            task.cancel()
            return
        }

        self.task?.cancel()
        self.task = task
    }

    func beginStop() -> Bool {
        guard !isStopping else {
            return false
        }

        isStopping = true
        task?.cancel()
        task = nil
        return true
    }

    func finishStop(succeeded: Bool, now: Date) -> RecordingLifecycleAutoStopTiming? {
        isStopping = false

        if succeeded {
            clearStoredState()
            return nil
        }

        return timing(at: now)
    }

    func clear() {
        clearStoredState()
        isStopping = false
    }

    private func timing(at now: Date) -> RecordingLifecycleAutoStopTiming? {
        guard let schedule,
            let maxRecordedDuration = schedule.maxRecordedDuration,
            let clock,
            clock.isRecording(at: now),
            let remaining = clock.remainingRecordedTime(for: schedule, at: now)
        else {
            return nil
        }

        return RecordingLifecycleAutoStopTiming(
            remaining: remaining,
            maxRecordedDuration: maxRecordedDuration
        )
    }

    private func clearStoredState() {
        task?.cancel()
        task = nil
        schedule = nil
        clock = nil
    }
}

private actor RecordingLifecycleOutputState {
    private(set) var plan: RecordingOutputFinalizationPlan?

    func set(_ plan: RecordingOutputFinalizationPlan) {
        self.plan = plan
    }

    func clear() {
        plan = nil
    }
}
