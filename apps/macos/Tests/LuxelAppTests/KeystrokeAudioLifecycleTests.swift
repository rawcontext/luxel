import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@testable import LuxelApp

@Suite("Audio keystroke lifecycle")
@MainActor
struct KeystrokeAudioLifecycleTests {
    @Test("audio stop invokes keystroke stop and save beside final media")
    func audioStopInvokesKeystrokeStopAndSave() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/luxel-audio-keystrokes.m4a")
        let fixture = makeModel(audioRecorder: KeystrokeAudioRecorderStub())
        let session = KeystrokeRecordingSessionSpy()
        fixture.model.keystrokeRecordingSession = session
        let activeRecording = try await fixture.model.audioRecordingLifecycleService.startRecording(
            AudioRecordingRequest(
                outputFileURL: outputURL,
                audio: .microphone(deviceID: "mic"),
                captureKeystrokes: true
            )
        )
        fixture.model.recordingState = .recording(
            activeRecording,
            RecordingMenuClock(startedAt: activeRecording.date)
        )

        _ = try await fixture.model.finishAudioRecordingStop()

        #expect(session.stopAndSaveURLs == [outputURL])
        #expect(session.cancelCount == 0)
    }

    @Test("terminal audio stop failure cancels keystroke capture")
    func terminalAudioStopFailureCancelsKeystrokeCapture() async {
        let fixture = makeModel(audioRecorder: KeystrokeAudioRecorderStub())
        let session = KeystrokeRecordingSessionSpy()
        fixture.model.keystrokeRecordingSession = session
        let activeRecording = ActiveRecording(
            fileURL: URL(fileURLWithPath: "/tmp/failed.m4a"),
            name: "Failed",
            date: Date(),
            options: RecordingOptions(
                frameRate: 0,
                captureKeystrokes: true,
                audio: .microphone(deviceID: "mic"),
                isAudioOnly: true
            )
        )
        let previousState = RecordingMenuState.recording(
            activeRecording,
            RecordingMenuClock(startedAt: activeRecording.date)
        )

        await fixture.model.handleRecordingStopFailure(
            RecordingLifecycleError.outputFinalizationFailed("failed"),
            context: RecordingStopContext(
                previousState: previousState,
                activeRecording: activeRecording,
                captureKind: .standard
            )
        )

        #expect(session.cancelCount == 1)
        #expect(fixture.model.recordingState == .idle)
    }

    private func makeModel(
        audioRecorder: any AudioRecorder
    ) -> (model: LuxelMenuModel, store: InMemoryRecordingHistoryStore) {
        let directory = URL(fileURLWithPath: "/tmp")
        let store = InMemoryRecordingHistoryStore()
        let history = RecordingHistoryService(
            store: store,
            fileSystem: KeystrokeLifecycleFileSystem(),
            dateProvider: KeystrokeLifecycleDateProvider(),
            mediaProbe: StaticMediaProbe(result: .playable)
        )
        return (
            LuxelMenuModel(
                settingsStore: KeystrokeLifecycleSettingsStore(
                    settings: AppSettings.defaults(recordingsDirectory: directory)
                ),
                recordingHistoryService: history,
                audioRecorder: audioRecorder
            ),
            store
        )
    }
}

@MainActor
private final class KeystrokeRecordingSessionSpy: KeystrokeRecordingSessionControlling {
    var isUserPaused = false
    private(set) var stopAndSaveURLs: [URL] = []
    private(set) var cancelCount = 0

    func start() {}
    func recordingDidPause() {}
    func recordingDidResume() {}
    func toggleUserPause() {}

    func stopAndSave(nextTo mediaURL: URL) async throws -> URL? {
        stopAndSaveURLs.append(mediaURL)
        return KeystrokeSidecarDocument.sidecarURL(nextTo: mediaURL)
    }

    func cancel() {
        cancelCount += 1
    }
}

private struct KeystrokeLifecycleSettingsStore: SettingsStore {
    let settings: AppSettings

    func load() throws -> AppSettings { settings }
    func save(_ settings: AppSettings) throws {}
}

private struct KeystrokeLifecycleDateProvider: DateProvider {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

private typealias KeystrokeLifecycleFileSystem = AlwaysExistingTestFileSystem

private final class KeystrokeAudioRecorderStub: AudioRecorder, @unchecked Sendable {
    func startRecording(_ request: AudioRecordingRequest) async throws {}
    func stopRecording() async throws {}
}
