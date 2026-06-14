import Foundation
import LuxelCore
import Testing

@Suite("Cursor timeline recording service")
struct CursorTimelineRecordingServiceTests {
    @Test("recording maps source events into media timeline")
    func recordingMapsSourceEventsIntoMediaTimeline() async throws {
        let arrow = try cursorImage(id: "arrow")
        let ibeam = try cursorImage(id: "ibeam")
        let source = StubCursorTimelineEventSource(events: [
            .sample(wallTime: 9, position: try CursorPoint(x: 90, y: 100), cursorImage: ibeam),
            .click(wallTime: 5.5, button: .left, phase: .down),
            .sample(wallTime: 1, position: try CursorPoint(x: 10, y: 20), cursorImage: arrow),
            .sample(wallTime: 6, position: try CursorPoint(x: 60, y: 70), cursorImage: arrow),
            .spotlightToggle(wallTime: 9.5),
            .click(wallTime: 9.75, button: .left, phase: .up)
        ])
        let service = CursorTimelineRecordingService(eventSource: source)
        let request = try CursorTimelineRecordingRequest(
            recordingDuration: 12,
            pauses: [MediaPauseInterval(start: 5, end: 7)]
        )

        let timeline = try await service.recordTimeline(request)

        #expect(timeline.samples == [
            try CursorSample(time: 1, position: CursorPoint(x: 10, y: 20), cursorImageID: "arrow"),
            try CursorSample(time: 7, position: CursorPoint(x: 90, y: 100), cursorImageID: "ibeam")
        ])
        #expect(timeline.clicks == [
            try CursorClickEvent(time: 7.75, button: .left, phase: .up)
        ])
        #expect(timeline.spotlightToggles == [7.5])
        #expect(timeline.cursorImages == [ibeam, arrow])
    }

    @Test("recording deduplicates cursor images by id")
    func recordingDeduplicatesCursorImagesByID() async throws {
        let arrow = try cursorImage(id: "arrow", pngData: Data([1]))
        let duplicateArrow = try cursorImage(id: "arrow", pngData: Data([2]))
        let source = StubCursorTimelineEventSource(events: [
            .sample(wallTime: 0, position: try CursorPoint(x: 0, y: 0), cursorImage: arrow),
            .sample(wallTime: 1, position: try CursorPoint(x: 1, y: 1), cursorImage: duplicateArrow)
        ])
        let service = CursorTimelineRecordingService(eventSource: source)

        let timeline = try await service.recordTimeline(
            CursorTimelineRecordingRequest(recordingDuration: 2)
        )

        #expect(timeline.cursorImages == [arrow])
        #expect(timeline.samples.map(\.cursorImageID) == ["arrow", "arrow"])
    }

    @Test("recording can save the timeline as a cursor sidecar")
    func recordingCanSaveTimelineAsCursorSidecar() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = CursorTimelineRecordingFileSystem()
        let source = StubCursorTimelineEventSource(events: [
            .sample(
                wallTime: 0.25,
                position: try CursorPoint(x: 3, y: 4),
                cursorImage: try cursorImage(id: "arrow")
            )
        ])
        let service = CursorTimelineRecordingService(
            eventSource: source,
            sidecarPersistence: CursorSidecarPersistenceService(fileSystem: fileSystem)
        )
        let bundle = RecordingBundle(rootURL: rootURL, manifest: try BundleManifest())

        let updatedBundle = try await service.recordAndSaveTimeline(
            CursorTimelineRecordingRequest(recordingDuration: 1),
            in: bundle
        )
        let expectedSidecar = try BundleSidecarManifest(kind: .cursor)

        #expect(updatedBundle.manifest.sidecar(for: .cursor) == expectedSidecar)
        #expect(fileSystem.writtenData.map(\.url) == [
            rootURL.appendingPathComponent("cursor.json"),
            rootURL.appendingPathComponent("bundle.json")
        ])

        let document = try JSONDecoder().decode(
            CursorSidecarDocument.self,
            from: try #require(fileSystem.writtenData.first?.data)
        )
        #expect(document.timeline.samples.map(\.time) == [0.25])
    }

    @Test("saving requires a sidecar persistence service")
    func savingRequiresSidecarPersistenceService() async throws {
        let service = CursorTimelineRecordingService(
            eventSource: StubCursorTimelineEventSource(events: [])
        )

        await #expect(throws: CursorTimelineRecordingServiceError.missingSidecarPersistence) {
            _ = try await service.recordAndSaveTimeline(
                CursorTimelineRecordingRequest(recordingDuration: 1),
                in: RecordingBundle(
                    rootURL: URL(fileURLWithPath: "/tmp/Luxel Recording"),
                    manifest: try BundleManifest()
                )
            )
        }
    }

    private func cursorImage(
        id: String,
        pngData: Data = Data([0x89, 0x50, 0x4E, 0x47])
    ) throws -> CursorImageAsset {
        try CursorImageAsset(
            id: id,
            pngData: pngData,
            hotspot: CursorPoint(x: 1, y: 2),
            scale: 2
        )
    }
}

private struct StubCursorTimelineEventSource: CursorTimelineEventSource {
    let sourceEvents: [CursorTimelineSourceEvent]

    init(events: [CursorTimelineSourceEvent]) {
        self.sourceEvents = events
    }

    func events() -> AsyncStream<CursorTimelineSourceEvent> {
        AsyncStream { continuation in
            for event in sourceEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class CursorTimelineRecordingFileSystem: FileSystem, @unchecked Sendable {
    private(set) var writtenData: [CursorTimelineRecordingWrittenData] = []

    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func readData(at url: URL) throws -> Data {
        throw FileSystemError.unsupportedRead(url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        writtenData.append(CursorTimelineRecordingWrittenData(data: data, url: url))
    }

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}

private struct CursorTimelineRecordingWrittenData: Equatable {
    let data: Data
    let url: URL
}
