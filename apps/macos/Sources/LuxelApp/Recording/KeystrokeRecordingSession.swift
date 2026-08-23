import Foundation
import LuxelCore

@MainActor
protocol KeystrokeRecordingSessionControlling: AnyObject {
    var isUserPaused: Bool { get }

    func start()
    func recordingDidPause()
    func recordingDidResume()
    func toggleUserPause()
    func stopAndSave(nextTo mediaURL: URL) async throws -> URL?
    func cancel()
}

@MainActor
final class KeystrokeRecordingSession: KeystrokeRecordingSessionControlling {
    private let sourceFactory: () -> any KeystrokeCaptureEventSource
    private let onStatus: (KeystrokeCaptureStatus) -> Void
    private let onChips: ([KeystrokeChip]) -> Void
    private var source: (any KeystrokeCaptureEventSource)?
    private var eventTask: Task<[KeystrokeSourceEvent], Never>?
    private var startedAtUptime: TimeInterval?
    private var recordingPauseStartedAt: TimeInterval?
    private var recordingPauses: [MediaPauseInterval] = []

    private(set) var status: KeystrokeCaptureStatus = .idle {
        didSet { onStatus(status) }
    }
    private(set) var isUserPaused = false

    init(
        sourceFactory: @escaping () -> any KeystrokeCaptureEventSource = {
            CGEventTapKeystrokeRecorder()
        },
        onStatus: @escaping (KeystrokeCaptureStatus) -> Void = { _ in },
        onChips: @escaping ([KeystrokeChip]) -> Void = { _ in }
    ) {
        self.sourceFactory = sourceFactory
        self.onStatus = onStatus
        self.onChips = onChips
    }

    func start() {
        guard source == nil else {
            return
        }

        let source = sourceFactory()
        let stream = source.events()
        self.source = source
        startedAtUptime = ProcessInfo.processInfo.systemUptime
        recordingPauses = []
        recordingPauseStartedAt = nil
        isUserPaused = false
        status = .active
        eventTask = Task {
            var events: [KeystrokeSourceEvent] = []
            for await event in stream {
                events.append(event)
                self.publishLiveChips(from: events)
            }
            return events
        }
        Task { [weak self] in
            for await status in source.statusUpdates {
                guard let self, self.source != nil else {
                    return
                }
                self.status = status
            }
        }
    }

    func recordingDidPause() {
        guard source != nil, recordingPauseStartedAt == nil else {
            return
        }
        recordingPauseStartedAt = elapsedTime
        source?.setRecordingPaused(true)
    }

    func recordingDidResume() {
        guard let start = recordingPauseStartedAt else {
            return
        }
        recordingPauseStartedAt = nil
        source?.setRecordingPaused(false)
        if let pause = try? MediaPauseInterval(start: start, end: elapsedTime) {
            recordingPauses.append(pause)
        }
    }

    func toggleUserPause() {
        guard let source else {
            return
        }
        isUserPaused.toggle()
        source.setUserPaused(isUserPaused)
    }

    func stopAndSave(nextTo mediaURL: URL) async throws -> URL? {
        guard let source, let eventTask else {
            return nil
        }
        if recordingPauseStartedAt != nil {
            recordingDidResume()
        }
        let duration = elapsedTime
        source.stop()
        let events = await eventTask.value
        reset()

        let request = try KeystrokeTimelineRecordingRequest(
            recordingDuration: duration,
            pauses: recordingPauses
        )
        let timeline = try KeystrokeTimelineRecordingService(eventSource: EmptyKeystrokeEventSource())
            .timeline(from: events, request: request)
        let document = try KeystrokeSidecarDocument(timeline: timeline)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sidecarURL = KeystrokeSidecarDocument.sidecarURL(nextTo: mediaURL)
        try encoder.encode(document).write(to: sidecarURL, options: .atomic)
        return sidecarURL
    }

    func cancel() {
        source?.stop()
        eventTask?.cancel()
        reset()
    }

    private var elapsedTime: TimeInterval {
        guard let startedAtUptime else {
            return 0
        }
        return max(0, ProcessInfo.processInfo.systemUptime - startedAtUptime)
    }

    private func reset() {
        source = nil
        eventTask = nil
        startedAtUptime = nil
        recordingPauseStartedAt = nil
        status = .idle
        isUserPaused = false
        onChips([])
    }

    private func publishLiveChips(from events: [KeystrokeSourceEvent]) {
        guard
            let request = try? KeystrokeTimelineRecordingRequest(
                recordingDuration: elapsedTime,
                pauses: recordingPauses
            ),
            let timeline = try? KeystrokeTimelineRecordingService(
                eventSource: EmptyKeystrokeEventSource()
            )
            .timeline(from: events, request: request),
            let chips = try? KeystrokeChipPlanner().plannedChips(for: timeline)
        else {
            return
        }
        onChips(KeystrokeOverlayLayout.activeChips(at: elapsedTime, in: chips))
    }
}

private struct EmptyKeystrokeEventSource: KeystrokeEventSource {
    func events() -> AsyncStream<KeystrokeSourceEvent> {
        AsyncStream { $0.finish() }
    }
}
