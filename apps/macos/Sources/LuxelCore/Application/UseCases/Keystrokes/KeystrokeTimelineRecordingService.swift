import Foundation

public struct KeystrokeTimelineRecordingRequest: Equatable, Sendable {
    public let recordingDuration: TimeInterval
    public let pauses: [MediaPauseInterval]

    public init(recordingDuration: TimeInterval, pauses: [MediaPauseInterval] = []) throws {
        _ = try MediaTimeMapper(recordingDuration: recordingDuration, pauses: pauses)
        self.recordingDuration = recordingDuration
        self.pauses = pauses
    }
}

public struct KeystrokeTimelineRecordingService: Sendable {
    private let eventSource: any KeystrokeEventSource
    private let sidecarPersistence: KeystrokeSidecarPersistenceService?

    public init(
        eventSource: any KeystrokeEventSource,
        sidecarPersistence: KeystrokeSidecarPersistenceService? = nil
    ) {
        self.eventSource = eventSource
        self.sidecarPersistence = sidecarPersistence
    }

    public func recordTimeline(_ request: KeystrokeTimelineRecordingRequest) async throws
        -> KeystrokeTimeline {
        var events: [KeystrokeSourceEvent] = []
        for await event in eventSource.events() {
            events.append(event)
        }

        return try timeline(from: events, request: request)
    }

    public func timeline(
        from events: [KeystrokeSourceEvent],
        request: KeystrokeTimelineRecordingRequest
    ) throws -> KeystrokeTimeline {
        let mapper = try MediaTimeMapper(
            recordingDuration: request.recordingDuration,
            pauses: request.pauses
        )
        var builder = KeystrokeTimelineRecordingBuilder(mapper: mapper)
        for event in events {
            try builder.append(event)
        }
        return try builder.timeline()
    }

    public func recordAndSaveTimeline(
        _ request: KeystrokeTimelineRecordingRequest,
        in bundle: RecordingBundle
    ) async throws -> RecordingBundle {
        guard let sidecarPersistence else {
            throw KeystrokeTimelineRecordingServiceError.missingSidecarPersistence
        }

        let timeline = try await recordTimeline(request)
        return try sidecarPersistence.save(timeline, in: bundle)
    }
}

public enum KeystrokeTimelineRecordingServiceError: Error, Equatable {
    case missingSidecarPersistence
}

private struct KeystrokeTimelineRecordingBuilder {
    private let mapper: MediaTimeMapper
    private var events: [KeystrokeEvent] = []
    private var pauseStarts: [KeystrokePauseCause: [TimeInterval]] = [:]
    private var pauses: [KeystrokePauseInterval] = []

    init(mapper: MediaTimeMapper) {
        self.mapper = mapper
    }

    mutating func append(_ event: KeystrokeSourceEvent) throws {
        switch event {
        case .keyDown(let wallTime, let keyCode, let characters, let modifiers, let isRepeat):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime) else {
                return
            }

            events.append(
                try KeystrokeEvent(
                    time: mediaTime,
                    kind: .keyDown,
                    keyCode: keyCode,
                    characters: characters,
                    modifiers: modifiers,
                    isRepeat: isRepeat
                ))

        case .flagsChanged(let wallTime, let keyCode, let modifiers):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime) else {
                return
            }

            events.append(
                try KeystrokeEvent(
                    time: mediaTime,
                    kind: .flagsChanged,
                    keyCode: keyCode,
                    modifiers: modifiers
                ))

        case .pauseStarted(let wallTime, let cause):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime) else {
                return
            }

            pauseStarts[cause, default: []].append(mediaTime)

        case .pauseEnded(let wallTime, let cause):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime),
                var starts = pauseStarts[cause],
                !starts.isEmpty
            else {
                return
            }

            let start = starts.removeLast()
            pauseStarts[cause] = starts
            guard mediaTime > start else {
                return
            }

            pauses.append(
                KeystrokePauseInterval(
                    timeRange: try TimeRange(start: start, end: mediaTime),
                    cause: cause
                ))
        }
    }

    func timeline() throws -> KeystrokeTimeline {
        var resolvedPauses = pauses
        for (cause, starts) in pauseStarts {
            for start in starts where mapper.mediaDuration > start {
                resolvedPauses.append(
                    KeystrokePauseInterval(
                        timeRange: try TimeRange(start: start, end: mapper.mediaDuration),
                        cause: cause
                    )
                )
            }
        }
        return try KeystrokeTimeline(
            events: events.sorted { $0.time < $1.time },
            pauses: resolvedPauses.sorted { $0.timeRange.start < $1.timeRange.start }
        )
    }
}
