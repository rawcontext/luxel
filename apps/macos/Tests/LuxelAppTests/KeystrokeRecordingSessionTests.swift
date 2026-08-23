import Foundation
import LuxelCore
import Testing

@testable import LuxelApp

@Suite("Keystroke recording session")
@MainActor
struct KeystrokeRecordingSessionTests {
    @Test("event source exists only between start and stop and saves sidecar")
    func eventSourceExistsOnlyBetweenStartAndStopAndSavesSidecar() async throws {
        let source = FakeKeystrokeCaptureEventSource()
        let directory = try temporaryKeystrokeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("recording.mp4")
        let session = KeystrokeRecordingSession(sourceFactory: { source })

        #expect(source.eventStreamCount == 0)
        session.start()
        await Task.yield()
        #expect(source.eventStreamCount == 1)
        #expect(source.stopCount == 0)

        source.yield(
            .keyDown(
                wallTime: 0,
                keyCode: 8,
                characters: "c",
                modifiers: [.command],
                isRepeat: false
            )
        )
        await Task.yield()
        let sidecarURL = try #require(await session.stopAndSave(nextTo: mediaURL))

        #expect(source.stopCount == 1)
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        let document = try JSONDecoder().decode(
            KeystrokeSidecarDocument.self,
            from: Data(contentsOf: sidecarURL)
        )
        #expect(document.timeline.events.count == 1)
        #expect(document.timeline.events.first?.characters == "c")
    }

    @Test("user pause is delegated only while a session is active")
    func userPauseIsDelegatedOnlyWhileSessionIsActive() {
        let source = FakeKeystrokeCaptureEventSource()
        let session = KeystrokeRecordingSession(sourceFactory: { source })

        session.toggleUserPause()
        #expect(source.userPauseValues.isEmpty)
        session.start()
        session.toggleUserPause()
        session.toggleUserPause()

        #expect(source.userPauseValues == [true, false])
    }

    @Test("audio-only stop ends capture and saves a sibling sidecar")
    func audioOnlyStopEndsCaptureAndSavesSidecar() async throws {
        let source = FakeKeystrokeCaptureEventSource()
        let directory = try temporaryKeystrokeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("recording.m4a")
        let session = KeystrokeRecordingSession(sourceFactory: { source })

        session.start()
        source.yield(
            .keyDown(
                wallTime: 0,
                keyCode: 0,
                characters: "a",
                modifiers: [],
                isRepeat: false
            )
        )
        let sidecarURL = try #require(await session.stopAndSave(nextTo: mediaURL))

        #expect(source.stopCount == 1)
        #expect(sidecarURL.lastPathComponent == "recording.keystrokes.json")
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    @Test("recording pause rejects typed events before they reach the sidecar")
    func recordingPauseRejectsTypedEvents() async throws {
        let source = FakeKeystrokeCaptureEventSource()
        let directory = try temporaryKeystrokeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = KeystrokeRecordingSession(sourceFactory: { source })
        session.start()

        session.recordingDidPause()
        source.yield(
            .keyDown(
                wallTime: 0,
                keyCode: 35,
                characters: "p",
                modifiers: [],
                isRepeat: false
            )
        )
        session.recordingDidResume()
        source.yield(
            .keyDown(
                wallTime: 0,
                keyCode: 31,
                characters: "o",
                modifiers: [],
                isRepeat: false
            )
        )
        let sidecarURL = try #require(
            await session.stopAndSave(nextTo: directory.appendingPathComponent("recording.mp4"))
        )
        let document = try JSONDecoder().decode(
            KeystrokeSidecarDocument.self,
            from: Data(contentsOf: sidecarURL)
        )

        #expect(source.recordingPauseValues == [true, false])
        #expect(document.timeline.events.map(\.characters) == ["o"])
    }

    @Test("session status consumer observes a recovered delivery interruption")
    func sessionStatusConsumerObservesRecoveredDeliveryInterruption() async {
        let source = FakeKeystrokeCaptureEventSource()
        var observedStatuses: [KeystrokeCaptureStatus] = []
        let session = KeystrokeRecordingSession(
            sourceFactory: { source },
            onStatus: { observedStatuses.append($0) }
        )
        session.start()
        while source.statusStreamCount == 0 {
            await Task.yield()
        }

        source.yieldStatus(.eventDeliveryRecovered)
        source.yieldStatus(.active)
        for _ in 0..<20 where !observedStatuses.contains(.eventDeliveryRecovered) {
            await Task.yield()
        }

        #expect(observedStatuses.contains(.eventDeliveryRecovered))
    }
}

private func temporaryKeystrokeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private final class FakeKeystrokeCaptureEventSource: KeystrokeCaptureEventSource,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var eventContinuation: AsyncStream<KeystrokeSourceEvent>.Continuation?
    private var statusContinuation: AsyncStream<KeystrokeCaptureStatus>.Continuation?
    private(set) var eventStreamCount = 0
    private(set) var statusStreamCount = 0
    private(set) var stopCount = 0
    private(set) var userPauseValues: [Bool] = []
    private(set) var recordingPauseValues: [Bool] = []
    private var isRecordingPaused = false

    var statusUpdates: AsyncStream<KeystrokeCaptureStatus> {
        AsyncStream { continuation in
            lock.withLock {
                statusStreamCount += 1
                statusContinuation = continuation
            }
            continuation.yield(.active)
        }
    }
    func events() -> AsyncStream<KeystrokeSourceEvent> {
        AsyncStream { continuation in
            lock.withLock {
                eventStreamCount += 1
                eventContinuation = continuation
            }
        }
    }

    func setUserPaused(_ isPaused: Bool) {
        lock.withLock {
            userPauseValues.append(isPaused)
        }
    }

    func setRecordingPaused(_ isPaused: Bool) {
        lock.withLock {
            recordingPauseValues.append(isPaused)
            isRecordingPaused = isPaused
        }
    }

    func stop() {
        let continuation = lock.withLock { () -> AsyncStream<KeystrokeSourceEvent>.Continuation? in
            stopCount += 1
            let continuation = eventContinuation
            eventContinuation = nil
            return continuation
        }
        continuation?.finish()
    }

    func yield(_ event: KeystrokeSourceEvent) {
        lock.withLock { isRecordingPaused ? nil : eventContinuation }?.yield(event)
    }

    func yieldStatus(_ status: KeystrokeCaptureStatus) {
        lock.withLock { statusContinuation }?.yield(status)
    }
}
