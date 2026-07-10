import Foundation
import LuxelCore
import Testing

extension RecordingLifecycleServiceTests {
    @Test("pause forwards to recorder while preserving active recording")
    func pauseForwardsToRecorderWhilePreservingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy()
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        try await service.pauseRecording()

        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
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
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(pauseError: RecordingLifecycleRecorderError.pauseFailed)
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        await #expect(throws: RecordingLifecycleRecorderError.pauseFailed) {
            try await service.pauseRecording()
        }
        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
    }

    @Test("resume forwards to recorder while preserving active recording")
    func resumeForwardsToRecorderWhilePreservingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy()
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        try await service.resumeRecording()

        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
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
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(resumeError: RecordingLifecycleRecorderError.resumeFailed)
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        await #expect(throws: RecordingLifecycleRecorderError.resumeFailed) {
            try await service.resumeRecording()
        }
        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
    }

    @Test("start schedules auto stop when request has max recorded duration")
    func startSchedulesAutoStop() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: RecordingLifecycleRecorderSpy(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)

        #expect(scheduler.scheduledIntervals == [60])
    }

    @Test("auto stop uses normal stop path")
    func autoStopUsesNormalStopPath() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let recorder = RecordingLifecycleRecorderSpy()
        let service = makeService(
            store: store,
            recorder: recorder,
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        let activeRecording = try await service.startRecording(request, name: "Timed")
        await scheduler.fireScheduledTask(at: 0)

        #expect(recorder.stopCount == 1)
        #expect(store.activeRecording == nil)
        #expect(store.recordings == [activeRecording.pastRecording])
    }

    @Test("auto stop notifies recording completion")
    func autoStopNotifiesRecordingCompletion() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let notifier = RecordingLifecycleUserNotifierSpy()
        let service = makeService(
            store: store,
            recorder: RecordingLifecycleRecorderSpy(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler,
            userNotifier: notifier
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        await scheduler.fireScheduledTask(at: 0)

        #expect(await notifier.recordingAutoStoppedDurations() == [60])
    }

    @Test("auto stop publishes stopped recording")
    func autoStopPublishesStoppedRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: RecordingLifecycleRecorderSpy(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))
        let stream = service.autoStoppedRecordings
        let eventTask = Task<PastRecording?, Never> {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        let activeRecording = try await service.startRecording(request)
        await scheduler.fireScheduledTask(at: 0)

        #expect(await eventTask.value == activeRecording.pastRecording)
    }

    @Test("pause suspends auto stop and resume schedules remaining recorded time")
    func pauseSuspendsAutoStopAndResumeSchedulesRemainingRecordedTime() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: RecordingLifecycleRecorderSpy(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        dateProvider.setDate(Date(timeIntervalSince1970: 1_010))
        try await service.pauseRecording()
        dateProvider.setDate(Date(timeIntervalSince1970: 1_040))
        try await service.resumeRecording()

        #expect(scheduler.scheduledIntervals == [60, 50])
        #expect(scheduler.isCanceled(at: 0))
        #expect(!scheduler.isCanceled(at: 1))
    }

    @Test("manual stop cancels pending auto stop")
    func manualStopCancelsPendingAutoStop() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let recorder = RecordingLifecycleRecorderSpy()
        let service = makeService(
            store: store,
            recorder: recorder,
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        _ = try await service.stopRecording()
        await scheduler.fireScheduledTask(at: 0)

        #expect(recorder.stopCount == 1)
        #expect(scheduler.isCanceled(at: 0))
    }

    @Test("manual stop does not notify recording auto stop")
    func manualStopDoesNotNotifyRecordingAutoStop() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = RecordingLifecycleMutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let notifier = RecordingLifecycleUserNotifierSpy()
        let service = makeService(
            store: store,
            recorder: RecordingLifecycleRecorderSpy(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler,
            userNotifier: notifier
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        _ = try await service.stopRecording()

        #expect(await notifier.recordingAutoStoppedDurations().isEmpty)
    }

}
