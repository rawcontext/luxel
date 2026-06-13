import Foundation

public struct RecordingSchedule: Codable, Equatable, Sendable {
    public let countdown: TimeInterval?
    public let maxRecordedDuration: TimeInterval?

    public init(
        countdown: TimeInterval? = nil,
        maxRecordedDuration: TimeInterval? = nil
    ) throws {
        if let countdown, !(1...60).contains(countdown) {
            throw RecordingScheduleError.invalidCountdown
        }

        if let maxRecordedDuration, !(1...43_200).contains(maxRecordedDuration) {
            throw RecordingScheduleError.invalidMaxRecordedDuration
        }

        self.countdown = countdown
        self.maxRecordedDuration = maxRecordedDuration
    }
}

public struct TimelapseOptions: Codable, Equatable, Sendable {
    public let speedFactor: Double
    public let playbackFrameRate: FrameRate

    public init(speedFactor: Double, playbackFrameRate: FrameRate) throws {
        guard speedFactor.isFinite, (2...240).contains(speedFactor) else {
            throw RecordingScheduleError.invalidTimelapseSpeed
        }

        self.speedFactor = speedFactor
        self.playbackFrameRate = playbackFrameRate
    }

    public var captureInterval: TimeInterval {
        speedFactor / Double(playbackFrameRate.framesPerSecond)
    }

    public func videoDuration(forWallDuration wallDuration: TimeInterval) -> TimeInterval {
        max(0, wallDuration) / speedFactor
    }
}

public struct RecordingClock: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let events: [RecordingClockEvent]

    public init(startedAt: Date, events: [RecordingClockEvent] = []) {
        self.startedAt = startedAt
        self.events = events
    }

    public func elapsedRecordedTime(at now: Date) -> TimeInterval {
        let now = max(startedAt, now)
        var elapsed: TimeInterval = 0
        var activeStart = startedAt
        var isRecording = true

        for event in events.sortedByDate where startedAt...now ~= event.date {
            switch event.kind {
            case .pause where isRecording:
                elapsed += event.date.timeIntervalSince(activeStart)
                isRecording = false
            case .resume where !isRecording:
                activeStart = event.date
                isRecording = true
            default:
                continue
            }
        }

        if isRecording {
            elapsed += now.timeIntervalSince(activeStart)
        }

        return max(0, elapsed)
    }

    public func remainingRecordedTime(for schedule: RecordingSchedule, at now: Date) -> TimeInterval? {
        guard let maxRecordedDuration = schedule.maxRecordedDuration else {
            return nil
        }

        return max(0, maxRecordedDuration - elapsedRecordedTime(at: now))
    }

    public func timerFireDate(for schedule: RecordingSchedule, at now: Date) -> Date? {
        guard let remaining = remainingRecordedTime(for: schedule, at: now) else {
            return nil
        }

        guard remaining > 0 else {
            return now
        }

        guard isRecording(at: now) else {
            return nil
        }

        return now.addingTimeInterval(remaining)
    }

    public func isRecording(at now: Date) -> Bool {
        let now = max(startedAt, now)
        var isRecording = true

        for event in events.sortedByDate where startedAt...now ~= event.date {
            switch event.kind {
            case .pause where isRecording:
                isRecording = false
            case .resume where !isRecording:
                isRecording = true
            default:
                continue
            }
        }

        return isRecording
    }
}

public struct RecordingClockEvent: Codable, Equatable, Sendable {
    public let kind: RecordingClockEventKind
    public let date: Date

    public init(kind: RecordingClockEventKind, date: Date) {
        self.kind = kind
        self.date = date
    }

    public static func pause(at date: Date) -> RecordingClockEvent {
        RecordingClockEvent(kind: .pause, date: date)
    }

    public static func resume(at date: Date) -> RecordingClockEvent {
        RecordingClockEvent(kind: .resume, date: date)
    }
}

public enum RecordingClockEventKind: String, Codable, Equatable, Sendable {
    case pause
    case resume
}

public enum RecordingScheduleError: Error, Equatable {
    case invalidCountdown
    case invalidMaxRecordedDuration
    case invalidTimelapseSpeed
}

private extension Array where Element == RecordingClockEvent {
    var sortedByDate: [RecordingClockEvent] {
        sorted { lhs, rhs in
            lhs.date < rhs.date
        }
    }
}
