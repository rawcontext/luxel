import Foundation
import LuxelCore
import Testing

extension RecordingLifecycleServiceTests {
    @Test("pause forwards to recorder while preserving active recording")
    func pauseForwardsToRecorderWhilePreservingActiveRecording() async throws {
        let recorder = RecordingLifecycleRecorderSpy()
        let context = makeActiveRecordingContext(recorder: recorder)

        try await context.service.pauseRecording()

        #expect(context.store.activeRecording == context.activeRecording)
        #expect(context.store.recordings.isEmpty)
        #expect(recorder.pauseCount == 1)
        #expect(recorder.resumeCount == 0)
    }

    @Test("pause rejects missing active recording")
    func pauseRejectsMissingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy()
        let service = makeService(store: store, recorder: recorder)

        await #expect(throws: RecordingLifecycleError.noActiveRecording) {
            try await service.pauseRecording()
        }
        #expect(recorder.pauseCount == 0)
    }

    @Test("pause keeps active recording when recorder fails")
    func pauseKeepsActiveRecordingWhenRecorderFails() async throws {
        let recorder = RecordingLifecycleRecorderSpy(pauseError: RecordingLifecycleRecorderError.pauseFailed)
        let context = makeActiveRecordingContext(recorder: recorder)

        await #expect(throws: RecordingLifecycleRecorderError.pauseFailed) {
            try await context.service.pauseRecording()
        }
        #expect(context.store.activeRecording == context.activeRecording)
        #expect(context.store.recordings.isEmpty)
    }

    @Test("resume forwards to recorder while preserving active recording")
    func resumeForwardsToRecorderWhilePreservingActiveRecording() async throws {
        let recorder = RecordingLifecycleRecorderSpy()
        let context = makeActiveRecordingContext(recorder: recorder)

        try await context.service.resumeRecording()

        #expect(context.store.activeRecording == context.activeRecording)
        #expect(context.store.recordings.isEmpty)
        #expect(recorder.pauseCount == 0)
        #expect(recorder.resumeCount == 1)
    }

    @Test("resume rejects missing active recording")
    func resumeRejectsMissingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy()
        let service = makeService(store: store, recorder: recorder)

        await #expect(throws: RecordingLifecycleError.noActiveRecording) {
            try await service.resumeRecording()
        }
        #expect(recorder.resumeCount == 0)
    }

    @Test("resume keeps active recording when recorder fails")
    func resumeKeepsActiveRecordingWhenRecorderFails() async throws {
        let recorder = RecordingLifecycleRecorderSpy(resumeError: RecordingLifecycleRecorderError.resumeFailed)
        let context = makeActiveRecordingContext(recorder: recorder)

        await #expect(throws: RecordingLifecycleRecorderError.resumeFailed) {
            try await context.service.resumeRecording()
        }
        #expect(context.store.activeRecording == context.activeRecording)
        #expect(context.store.recordings.isEmpty)
    }

    @Test("start schedules auto stop when request has max recorded duration")
    func startSchedulesAutoStop() async throws {
        let context = try makeAutoStopContext()

        _ = try await context.service.startRecording(context.request)

        #expect(context.scheduler.scheduledIntervals == [60])
    }

    @Test("auto stop uses normal stop path")
    func autoStopUsesNormalStopPath() async throws {
        let recorder = RecordingLifecycleRecorderSpy()
        let context = try makeAutoStopContext(recorder: recorder)

        let activeRecording = try await context.service.startRecording(context.request, name: "Timed")
        await context.scheduler.fireScheduledTask(at: 0)

        #expect(recorder.stopCount == 1)
        #expect(context.store.activeRecording == nil)
        #expect(context.store.recordings == [activeRecording.pastRecording])
    }

    @Test("auto stop notifies recording completion")
    func autoStopNotifiesRecordingCompletion() async throws {
        let notifier = RecordingLifecycleUserNotifierSpy()
        let context = try makeAutoStopContext(userNotifier: notifier)

        _ = try await context.service.startRecording(context.request)
        await context.scheduler.fireScheduledTask(at: 0)

        #expect(await notifier.recordingAutoStoppedDurations() == [60])
    }

    @Test("auto stop publishes stopped recording")
    func autoStopPublishesStoppedRecording() async throws {
        let context = try makeAutoStopContext()
        let stream = context.service.autoStoppedRecordings
        let eventTask = Task<PastRecording?, Never> {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        let activeRecording = try await context.service.startRecording(context.request)
        await context.scheduler.fireScheduledTask(at: 0)

        #expect(await eventTask.value == activeRecording.pastRecording)
    }

    @Test("pause suspends auto stop and resume schedules remaining recorded time")
    func pauseSuspendsAutoStopAndResumeSchedulesRemainingRecordedTime() async throws {
        let context = try makeAutoStopContext()

        _ = try await context.service.startRecording(context.request)
        context.dateProvider.setDate(Date(timeIntervalSince1970: 1_010))
        try await context.service.pauseRecording()
        context.dateProvider.setDate(Date(timeIntervalSince1970: 1_040))
        try await context.service.resumeRecording()

        #expect(context.scheduler.scheduledIntervals == [60, 50])
        #expect(context.scheduler.isCanceled(at: 0))
        #expect(!context.scheduler.isCanceled(at: 1))
    }

    @Test("manual stop cancels pending auto stop")
    func manualStopCancelsPendingAutoStop() async throws {
        let recorder = RecordingLifecycleRecorderSpy()
        let context = try makeAutoStopContext(recorder: recorder)

        _ = try await context.service.startRecording(context.request)
        _ = try await context.service.stopRecording()
        await context.scheduler.fireScheduledTask(at: 0)

        #expect(recorder.stopCount == 1)
        #expect(context.scheduler.isCanceled(at: 0))
    }

    @Test("manual stop does not notify recording auto stop")
    func manualStopDoesNotNotifyRecordingAutoStop() async throws {
        let notifier = RecordingLifecycleUserNotifierSpy()
        let context = try makeAutoStopContext(userNotifier: notifier)

        _ = try await context.service.startRecording(context.request)
        _ = try await context.service.stopRecording()

        #expect(await notifier.recordingAutoStoppedDurations().isEmpty)
    }

}

private struct ActiveRecordingContext {
    let store: InMemoryRecordingHistoryStore
    let service: RecordingLifecycleService
    let activeRecording: ActiveRecording
}

private struct AutoStopContext {
    let store: InMemoryRecordingHistoryStore
    let dateProvider: RecordingLifecycleMutableDateProvider
    let scheduler: RecordingLifecycleAutoStopScheduler
    let service: RecordingLifecycleService
    let request: RecordingRequest
}

private extension RecordingLifecycleServiceTests {
    func makeActiveRecordingContext(
        recorder: RecordingLifecycleRecorderSpy
    ) -> ActiveRecordingContext {
        let store = InMemoryRecordingHistoryStore()
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )
        return ActiveRecordingContext(
            store: store,
            service: service,
            activeRecording: activeRecording
        )
    }

    func makeAutoStopContext(
        recorder: RecordingLifecycleRecorderSpy = RecordingLifecycleRecorderSpy(),
        userNotifier: RecordingLifecycleUserNotifierSpy = RecordingLifecycleUserNotifierSpy()
    ) throws -> AutoStopContext {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: recorder,
            dateProvider: dateProvider,
            autoStopScheduler: scheduler,
            userNotifier: userNotifier
        )
        return try AutoStopContext(
            store: store,
            dateProvider: dateProvider,
            scheduler: scheduler,
            service: service,
            request: makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))
        )
    }
}
