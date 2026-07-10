import Foundation
import LuxelCore
import Testing

@Suite("Keystroke timeline recording service")
struct KeystrokeTimelineRecordingServiceTests {
    @Test("recording maps source events into media timeline")
    func recordingMapsSourceEventsIntoMediaTimeline() async throws {
        let source = StubKeystrokeEventSource(events: sourceEvents())
        let service = KeystrokeTimelineRecordingService(eventSource: source)
        let request = try KeystrokeTimelineRecordingRequest(
            recordingDuration: 12,
            pauses: [MediaPauseInterval(start: 5, end: 7)]
        )

        let timeline = try await service.recordTimeline(request)

        #expect(
            timeline.events == [
                try KeystrokeEvent(
                    time: 1,
                    kind: .flagsChanged,
                    keyCode: 55,
                    modifiers: [.command]
                ),
                try KeystrokeEvent(
                    time: 7,
                    kind: .keyDown,
                    keyCode: 40,
                    characters: "k",
                    modifiers: [.command, .shift]
                ),
                try KeystrokeEvent(
                    time: 7.5,
                    kind: .keyDown,
                    keyCode: 123,
                    isRepeat: true
                )
            ])
        #expect(timeline.pauses.isEmpty)
    }

    private func sourceEvents() -> [KeystrokeSourceEvent] {
        [
            .keyDown(
                wallTime: 9,
                keyCode: 40,
                characters: "k",
                modifiers: [.command, .shift],
                isRepeat: false
            ),
            .keyDown(
                wallTime: 5.5,
                keyCode: 8,
                characters: "c",
                modifiers: [],
                isRepeat: false
            ),
            .flagsChanged(wallTime: 1, keyCode: 55, modifiers: [.command]),
            .keyDown(
                wallTime: 13,
                keyCode: 9,
                characters: "v",
                modifiers: [],
                isRepeat: false
            ),
            .keyDown(
                wallTime: 9.5,
                keyCode: 123,
                characters: nil,
                modifiers: [],
                isRepeat: true
            )
        ]
    }

    @Test("recording maps source pause windows into media timeline")
    func recordingMapsSourcePauseWindowsIntoMediaTimeline() async throws {
        let source = StubKeystrokeEventSource(events: [
            .pauseEnded(wallTime: 0.5, cause: .user),
            .pauseStarted(wallTime: 1, cause: .secureInput),
            .keyDown(
                wallTime: 1.25,
                keyCode: 0,
                characters: "a",
                modifiers: [],
                isRepeat: false
            ),
            .pauseEnded(wallTime: 2, cause: .secureInput),
            .pauseStarted(wallTime: 7.5, cause: .user),
            .pauseEnded(wallTime: 8.5, cause: .user)
        ])
        let service = KeystrokeTimelineRecordingService(eventSource: source)
        let request = try KeystrokeTimelineRecordingRequest(
            recordingDuration: 10,
            pauses: [MediaPauseInterval(start: 4, end: 6)]
        )

        let timeline = try await service.recordTimeline(request)

        #expect(
            timeline.pauses == [
                KeystrokePauseInterval(
                    timeRange: try TimeRange(start: 1, end: 2),
                    cause: .secureInput
                ),
                KeystrokePauseInterval(
                    timeRange: try TimeRange(start: 5.5, end: 6.5),
                    cause: .user
                )
            ])
        #expect(timeline.eventsOutsidePauses().isEmpty)
    }

    @Test("recording can save the timeline as a keystroke sidecar")
    func recordingCanSaveTimelineAsKeystrokeSidecar() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = KeystrokeTimelineRecordingFileSystem()
        let source = StubKeystrokeEventSource(events: [
            .keyDown(
                wallTime: 0.25,
                keyCode: 8,
                characters: "c",
                modifiers: [.command],
                isRepeat: false
            )
        ])
        let service = KeystrokeTimelineRecordingService(
            eventSource: source,
            sidecarPersistence: KeystrokeSidecarPersistenceService(fileSystem: fileSystem)
        )
        let bundle = RecordingBundle(rootURL: rootURL, manifest: try BundleManifest())

        let updatedBundle = try await service.recordAndSaveTimeline(
            KeystrokeTimelineRecordingRequest(recordingDuration: 1),
            in: bundle
        )
        let expectedSidecar = try BundleSidecarManifest(kind: .keystrokes)

        #expect(updatedBundle.manifest.sidecar(for: .keystrokes) == expectedSidecar)
        #expect(
            fileSystem.writtenData.map(\.url) == [
                rootURL.appendingPathComponent("keystrokes.json"),
                rootURL.appendingPathComponent("bundle.json")
            ])

        let document = try JSONDecoder().decode(
            KeystrokeSidecarDocument.self,
            from: try #require(fileSystem.writtenData.first?.data)
        )
        #expect(document.timeline.events.map(\.time) == [0.25])
    }

    @Test("saving requires a sidecar persistence service")
    func savingRequiresSidecarPersistenceService() async throws {
        let service = KeystrokeTimelineRecordingService(
            eventSource: StubKeystrokeEventSource(events: [])
        )

        await #expect(throws: KeystrokeTimelineRecordingServiceError.missingSidecarPersistence) {
            _ = try await service.recordAndSaveTimeline(
                KeystrokeTimelineRecordingRequest(recordingDuration: 1),
                in: RecordingBundle(
                    rootURL: URL(fileURLWithPath: "/tmp/Luxel Recording"),
                    manifest: try BundleManifest()
                )
            )
        }
    }
}

private struct StubKeystrokeEventSource: KeystrokeEventSource {
    let sourceEvents: [KeystrokeSourceEvent]

    init(events: [KeystrokeSourceEvent]) {
        self.sourceEvents = events
    }

    func events() -> AsyncStream<KeystrokeSourceEvent> {
        AsyncStream { continuation in
            for event in sourceEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class KeystrokeTimelineRecordingFileSystem: FileSystem, @unchecked Sendable {
    private(set) var writtenData: [KeystrokeTimelineRecordingWrittenData] = []

    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func readData(at url: URL) throws -> Data {
        throw FileSystemError.unsupportedRead(url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        writtenData.append(KeystrokeTimelineRecordingWrittenData(data: data, url: url))
    }

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}

private struct KeystrokeTimelineRecordingWrittenData: Equatable {
    let data: Data
    let url: URL
}
