import Foundation

public final class RecordingLifecycleService: Sendable {
    private let recorder: any CaptureRecorder
    private let history: RecordingHistoryService
    private let dateProvider: any DateProvider
    private let autoStopScheduler: any RecordingAutoStopScheduler
    private let userNotifier: (any UserNotifier)?
    private let autoStopState = RecordingLifecycleAutoStopState()

    public init(
        recorder: any CaptureRecorder,
        history: RecordingHistoryService,
        dateProvider: any DateProvider = SystemDateProvider(),
        autoStopScheduler: any RecordingAutoStopScheduler = TaskRecordingAutoStopScheduler(),
        userNotifier: (any UserNotifier)? = nil
    ) {
        self.recorder = recorder
        self.history = history
        self.dateProvider = dateProvider
        self.autoStopScheduler = autoStopScheduler
        self.userNotifier = userNotifier
    }

    @discardableResult
    public func startRecording(
        _ request: RecordingRequest,
        name: String? = nil
    ) async throws -> ActiveRecording {
        let activeRecording = history.setCurrentRecording(
            fileURL: request.outputFileURL,
            name: name,
            options: request.recordingOptions
        )

        do {
            try await recorder.startRecording(request)
            await startAutoStopIfNeeded(schedule: request.schedule, startedAt: activeRecording.date)
            return activeRecording
        } catch {
            await autoStopState.clear()
            history.clearCurrentRecording()
            throw error
        }
    }

    public func pauseRecording() async throws {
        guard history.getCurrentRecording() != nil else {
            throw RecordingLifecycleError.noActiveRecording
        }

        try await recorder.pauseRecording()
        await autoStopState.pause(at: dateProvider.now())
    }

    public func resumeRecording() async throws {
        guard history.getCurrentRecording() != nil else {
            throw RecordingLifecycleError.noActiveRecording
        }

        try await recorder.resumeRecording()
        await rescheduleAutoStopIfNeeded(await autoStopState.resume(at: dateProvider.now()))
    }

    @discardableResult
    public func stopRecording(recordingName: String? = nil) async throws -> PastRecording {
        guard await autoStopState.beginStop() else {
            throw RecordingLifecycleError.stopAlreadyInProgress
        }

        do {
            try await recorder.stopRecording()

            guard let recording = history.stopCurrentRecording(recordingName: recordingName) else {
                await finishStop(succeeded: false)
                throw RecordingLifecycleError.noActiveRecording
            }

            await autoStopState.clear()
            return recording
        } catch {
            await finishStop(succeeded: false)
            throw error
        }
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
            guard let self else {
                return
            }

            guard (try? await self.stopRecording()) != nil else {
                return
            }

            try? await self.userNotifier?.notifyRecordingAutoStopped(duration: timing.maxRecordedDuration)
        }
        await autoStopState.setTask(task)
    }
}

public enum RecordingLifecycleError: Error, Equatable {
    case noActiveRecording
    case stopAlreadyInProgress
}

private struct RecordingLifecycleAutoStopTiming: Sendable {
    let remaining: TimeInterval
    let maxRecordedDuration: TimeInterval
}

private actor RecordingLifecycleAutoStopState {
    private var schedule: RecordingSchedule?
    private var clock: RecordingClock?
    private var task: (any RecordingAutoStopTask)?
    private var isStopping = false

    func start(schedule: RecordingSchedule, startedAt: Date, now: Date) -> RecordingLifecycleAutoStopTiming? {
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
              let remaining = clock.remainingRecordedTime(for: schedule, at: now) else {
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
