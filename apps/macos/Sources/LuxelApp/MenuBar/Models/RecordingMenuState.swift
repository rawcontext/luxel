import Foundation
import LuxelCore

enum RecordingMenuState: Equatable {
    case idle
    case starting
    case countingDown(startedAt: Date, duration: TimeInterval)
    case recording(ActiveRecording, RecordingMenuClock)
    case pausing(ActiveRecording, RecordingMenuClock)
    case paused(ActiveRecording, RecordingMenuClock)
    case resuming(ActiveRecording, RecordingMenuClock)
    case stopping
    case exporting(ExportProgressSnapshot)
    case failed(String)
}

enum RecordingStopAction {
    case openEditor(URL)
    case quickExported(URL)
    case audioRecorded(URL)
}

extension RecordingStopAction {
    var loggingDescription: String {
        switch self {
        case .openEditor:
            "openEditor"
        case .quickExported:
            "quickExported"
        case .audioRecorded:
            "audioRecorded"
        }
    }
}

struct RecordingMenuClock: Equatable {
    let startedAt: Date
    var pausedAt: Date?
    var accumulatedPausedDuration: TimeInterval

    init(
        startedAt: Date,
        pausedAt: Date? = nil,
        accumulatedPausedDuration: TimeInterval = 0
    ) {
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedPausedDuration = accumulatedPausedDuration
    }

    func elapsed(at now: Date) -> TimeInterval {
        let endDate = pausedAt ?? now
        return max(0, endDate.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }

    func paused(at now: Date) -> RecordingMenuClock {
        RecordingMenuClock(
            startedAt: startedAt,
            pausedAt: now,
            accumulatedPausedDuration: accumulatedPausedDuration
        )
    }

    func resumed(at now: Date) -> RecordingMenuClock {
        RecordingMenuClock(
            startedAt: startedAt,
            pausedAt: nil,
            accumulatedPausedDuration: accumulatedPausedDuration + pausedDuration(endingAt: now)
        )
    }

    private func pausedDuration(endingAt now: Date) -> TimeInterval {
        guard let pausedAt else {
            return 0
        }

        return max(0, now.timeIntervalSince(pausedAt))
    }
}

extension RecordingMenuState {
    var loggingDescription: String {
        switch self {
        case .idle:
            "idle"
        case .starting:
            "starting"
        case .countingDown:
            "countingDown"
        case .recording:
            "recording"
        case .pausing:
            "pausing"
        case .paused:
            "paused"
        case .resuming:
            "resuming"
        case .stopping:
            "stopping"
        case .exporting:
            "exporting"
        case .failed:
            "failed"
        }
    }

    func presentationState(now: Date) -> RecordingSessionPresentationState {
        switch self {
        case .idle:
            .idle
        case .starting:
            .starting
        case .countingDown(let startedAt, let duration):
            .countingDown(remaining: max(0, duration - now.timeIntervalSince(startedAt)))
        case .recording(let recording, let clock):
            presentationState(for: recording, clock: clock, now: now, phase: .recording)
        case .pausing(let recording, let clock):
            presentationState(for: recording, clock: clock, now: now, phase: .pausing)
        case .paused(let recording, let clock):
            presentationState(for: recording, clock: clock, now: now, phase: .paused)
        case .resuming(let recording, let clock):
            presentationState(for: recording, clock: clock, now: now, phase: .resuming)
        case .stopping:
            .stopping
        case .exporting(let snapshot):
            .exporting(snapshot)
        case .failed(let message):
            .failed(message)
        }
    }

    var activeRecording: ActiveRecording? {
        switch self {
        case .recording(let recording, _),
             .pausing(let recording, _),
             .paused(let recording, _),
             .resuming(let recording, _):
            recording
        case .idle, .starting, .countingDown, .stopping, .exporting, .failed:
            nil
        }
    }

    private enum ActivePresentationPhase {
        case recording
        case pausing
        case paused
        case resuming
    }

    private func presentationState(
        for recording: ActiveRecording,
        clock: RecordingMenuClock,
        now: Date,
        phase: ActivePresentationPhase
    ) -> RecordingSessionPresentationState {
        let elapsed = clock.elapsed(at: now)
        let remaining = remainingRecordedTime(for: recording, elapsed: elapsed)

        switch phase {
        case .recording:
            return .recording(elapsed: elapsed, remaining: remaining)
        case .pausing:
            return .pausing(elapsed: elapsed, remaining: remaining)
        case .paused:
            return .paused(elapsed: elapsed, remaining: remaining)
        case .resuming:
            return .resuming(elapsed: elapsed, remaining: remaining)
        }
    }

    private func remainingRecordedTime(for recording: ActiveRecording, elapsed: TimeInterval) -> TimeInterval? {
        guard let maxRecordedDuration = recording.options.schedule?.maxRecordedDuration else {
            return nil
        }

        return max(0, maxRecordedDuration - elapsed)
    }
}
