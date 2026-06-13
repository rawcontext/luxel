import Foundation
import LuxelCore

enum RecordingMenuState: Equatable {
    case idle
    case starting
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
    func presentationState(now: Date) -> RecordingSessionPresentationState {
        switch self {
        case .idle:
            .idle
        case .starting:
            .starting
        case .recording(_, let clock):
            .recording(elapsed: clock.elapsed(at: now))
        case .pausing(_, let clock):
            .pausing(elapsed: clock.elapsed(at: now))
        case .paused(_, let clock):
            .paused(elapsed: clock.elapsed(at: now))
        case .resuming(_, let clock):
            .resuming(elapsed: clock.elapsed(at: now))
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
        case .idle, .starting, .stopping, .exporting, .failed:
            nil
        }
    }
}
