import Foundation

public struct CursorTimelineRecordingRequest: Equatable, Sendable {
    public let recordingDuration: TimeInterval
    public let pauses: [MediaPauseInterval]
    public let captureFrame: CaptureRect?

    public init(
        recordingDuration: TimeInterval,
        pauses: [MediaPauseInterval] = [],
        captureFrame: CaptureRect? = nil
    ) throws {
        _ = try MediaTimeMapper(recordingDuration: recordingDuration, pauses: pauses)
        self.recordingDuration = recordingDuration
        self.pauses = pauses
        self.captureFrame = captureFrame
    }
}

public struct CursorTimelineRecordingService: Sendable {
    private let eventSource: any CursorTimelineEventSource
    private let sidecarPersistence: CursorSidecarPersistenceService?

    public init(
        eventSource: any CursorTimelineEventSource,
        sidecarPersistence: CursorSidecarPersistenceService? = nil
    ) {
        self.eventSource = eventSource
        self.sidecarPersistence = sidecarPersistence
    }

    public func recordTimeline(_ request: CursorTimelineRecordingRequest) async throws
    -> CursorTimeline {
        let mapper = try MediaTimeMapper(
            recordingDuration: request.recordingDuration,
            pauses: request.pauses
        )
        var builder = CursorTimelineRecordingBuilder(
            mapper: mapper,
            captureFrame: request.captureFrame
        )

        for await event in eventSource.events() {
            try builder.append(event)
        }

        return try builder.timeline()
    }

    public func recordAndSaveTimeline(
        _ request: CursorTimelineRecordingRequest,
        in bundle: RecordingBundle
    ) async throws -> RecordingBundle {
        guard let sidecarPersistence else {
            throw CursorTimelineRecordingServiceError.missingSidecarPersistence
        }

        let timeline = try await recordTimeline(request)
        return try sidecarPersistence.save(timeline, in: bundle)
    }
}

public enum CursorTimelineRecordingServiceError: Error, Equatable {
    case missingSidecarPersistence
}

private struct CursorTimelineRecordingBuilder {
    private let mapper: MediaTimeMapper
    private let captureFrame: CaptureRect?
    private var samples: [CursorSample] = []
    private var clicks: [CursorClickEvent] = []
    private var spotlightToggles: [TimeInterval] = []
    private var cursorImages: [CursorImageAsset] = []
    private var cursorImageIDs: Set<String> = []

    init(mapper: MediaTimeMapper, captureFrame: CaptureRect?) {
        self.mapper = mapper
        self.captureFrame = captureFrame
    }

    mutating func append(_ event: CursorTimelineSourceEvent) throws {
        switch event {
        case .sample(let wallTime, let position, let cursorImage):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime) else {
                return
            }

            let localPosition =
                try captureFrame.map {
                    try CursorCoordinateMapper.localPoint(fromGlobalPoint: position, in: $0)
                } ?? position

            appendCursorImageIfNeeded(cursorImage)
            samples.append(
                try CursorSample(
                    time: mediaTime,
                    position: localPosition,
                    cursorImageID: cursorImage.id
                ))

        case .click(let wallTime, let button, let phase):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime) else {
                return
            }

            clicks.append(try CursorClickEvent(time: mediaTime, button: button, phase: phase))

        case .spotlightToggle(let wallTime):
            guard let mediaTime = mapper.mediaTime(forWallTime: wallTime) else {
                return
            }

            spotlightToggles.append(mediaTime)
        }
    }

    func timeline() throws -> CursorTimeline {
        try CursorTimeline(
            samples: samples.sorted { $0.time < $1.time },
            clicks: clicks.sorted { $0.time < $1.time },
            spotlightToggles: spotlightToggles.sorted(),
            cursorImages: cursorImages
        )
    }

    private mutating func appendCursorImageIfNeeded(_ cursorImage: CursorImageAsset) {
        guard cursorImageIDs.insert(cursorImage.id).inserted else {
            return
        }

        cursorImages.append(cursorImage)
    }
}
