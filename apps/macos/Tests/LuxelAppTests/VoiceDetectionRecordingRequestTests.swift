import Foundation
@testable import LuxelApp
@testable import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Voice detection recording requests")
@MainActor
struct VoiceDetectionRecordingRequestTests {
    @Test(
        "prompted request always captures the selected microphone and conditionally system audio",
        arguments: [true, false]
    )
    func promptedRequestSources(includeSystemAudio: Bool) throws {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/voice-detection-recordings")
        var settings = AppSettings.defaults(recordingsDirectory: recordingsDirectory)
        settings.recordAudio = false
        settings.recordSystemAudio = includeSystemAudio
        settings.audioOnlyFormat = .alac
        settings.audioInputDeviceID = "mic-1"
        settings.audioInputDeviceName = "Test Mic"
        settings.keystrokeOverlayEnabled = true
        let model = makeModel(settings: settings)
        model.microphoneStatus = .authorized
        model.screenRecordingStatus = .authorized

        let request = try model.makeSpeechPromptAudioRecordingRequest(
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(request.audio == (includeSystemAudio
                                    ? .systemAndMicrophone(deviceID: "mic-1")
                                    : .microphone(deviceID: "mic-1")))
        #expect(request.format == .alac)
        #expect(!request.captureKeystrokes)
        #expect(request.outputFileURL.deletingLastPathComponent().path == recordingsDirectory.path)
        #expect(request.outputFileURL.pathExtension == "m4a")
    }

    @Test("prompted request rejects a missing explicit microphone without fallback")
    func missingMicrophone() {
        var settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp"))
        settings.audioInputDeviceID = "missing-mic"
        settings.audioInputDeviceName = "Missing Mic"
        let model = makeModel(settings: settings)
        model.microphoneStatus = .authorized

        #expect(throws: VoiceDetectionRecordingRequestError.selectedMicrophoneUnavailable) {
            _ = try model.makeSpeechPromptAudioRecordingRequest()
        }
    }

    @Test("explicit prompt action releases detection before starting one audio recording")
    func promptActionStartsAfterDetectorRelease() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VoiceDetectionRecordingRequestTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makePromptRecordingFixture(root: root)

        await fixture.model.refreshPermissions()
        await fixture.model.reconcileVoiceDetection()
        for index in 0..<4 {
            await fixture.coordinator.receive(.observation(
                VoiceActivityObservation(
                    probability: 0.95,
                    observedAt: Date(timeIntervalSince1970: Double(index) * 0.25)
                )
            ))
        }

        await fixture.model.handleVoiceDetectionPromptAction(.startRecording)

        let requests = await fixture.recorder.requests
        let events = await fixture.timeline.events
        #expect(requests.count == 1)
        #expect(requests.first?.audio == .microphone(deviceID: "mic-1"))
        #expect(requests.first?.captureKeystrokes == false)
        #expect(events.firstIndex(of: "stop-detector")! < events.firstIndex(of: "start-recorder")!)
        #expect(fixture.model.recordingState.activeRecording?.options.isAudioOnly == true)

        if let stagingDirectory = requests.first?.outputFileURL.deletingLastPathComponent(),
           stagingDirectory.path.hasPrefix(
            FileManager.default.temporaryDirectory
                .appending(path: "Luxel/Recordings")
                .path
           ) {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }
    }

    @Test("prompt and manual recording starts race to one recorder request")
    func promptAndManualStartRace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VoiceDetectionRecordingRaceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makePromptRecordingFixture(root: root)

        await fixture.model.refreshPermissions()
        await fixture.model.reconcileVoiceDetection()
        for index in 0..<4 {
            await fixture.coordinator.receive(.observation(
                VoiceActivityObservation(
                    probability: 0.95,
                    observedAt: Date(timeIntervalSince1970: Double(index) * 0.25)
                )
            ))
        }

        async let promptStart: Void = fixture.model.handleVoiceDetectionPromptAction(.startRecording)
        async let manualStart: Void = fixture.model.startAudioOnlyRecording()
        _ = await (promptStart, manualStart)

        #expect(await fixture.recorder.requests.count == 1)
        #expect(fixture.model.recordingState.activeRecording?.options.isAudioOnly == true)
    }

    private func makePromptRecordingFixture(
        root: URL
    ) throws -> VoiceDetectionPromptFixture {
        let modelDirectory = root
            .appending(path: "Models/voice-activity-detection")
            .appending(path: BundledVoiceActivityModelLocator.modelDirectoryName)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        var settings = AppSettings.defaults(recordingsDirectory: root.appending(path: "Recordings"))
        settings.speechDetectionPromptsEnabled = true
        settings.speechDetectionDisclosureAccepted = true
        settings.recordAudio = true
        settings.recordSystemAudio = false
        settings.audioInputDeviceID = "mic-1"
        settings.audioInputDeviceName = "Test Mic"
        let timeline = VoiceDetectionRecordingTimeline()
        let coordinator = VoiceDetectionCoordinator(
            detector: VoiceDetectionDetectorSpy(timeline: timeline),
            notifier: VoiceDetectionNotifierSpy(timeline: timeline)
        )
        let recorder = VoiceDetectionAudioRecorderSpy(timeline: timeline)
        let history = RecordingHistoryService(
            store: InMemoryRecordingHistoryStore(),
            fileSystem: AlwaysExistingTestFileSystem(),
            dateProvider: VoiceDetectionDateProvider(),
            mediaProbe: StaticMediaProbe(result: .playable)
        )
        let model = LuxelMenuModel(
            settingsStore: VoiceDetectionSettingsStore(settings: settings),
            permissionClient: VoiceDetectionPermissionClient(),
            recordingHistoryService: history,
            audioInputDeviceService: AudioInputDeviceService(
                catalog: VoiceDetectionAudioInputCatalog()
            ),
            voiceDetectionCoordinator: coordinator,
            voiceDetectionModelLocator: BundledVoiceActivityModelLocator(resourceURL: root),
            systemActivityMonitor: VoiceDetectionSystemActivityMonitor(),
            audioRecorder: recorder
        )
        return VoiceDetectionPromptFixture(
            model: model,
            coordinator: coordinator,
            recorder: recorder,
            timeline: timeline
        )
    }

    private func makeModel(settings: AppSettings) -> LuxelMenuModel {
        LuxelMenuModel(
            settingsStore: VoiceDetectionSettingsStore(settings: settings),
            audioInputDeviceService: AudioInputDeviceService(
                catalog: VoiceDetectionAudioInputCatalog()
            )
        )
    }
}

@MainActor
private struct VoiceDetectionPromptFixture {
    let model: LuxelMenuModel
    let coordinator: VoiceDetectionCoordinator
    let recorder: VoiceDetectionAudioRecorderSpy
    let timeline: VoiceDetectionRecordingTimeline
}

private struct VoiceDetectionSettingsStore: SettingsStore {
    let settings: AppSettings

    func load() throws -> AppSettings { settings }
    func save(_ settings: AppSettings) throws {}
}

private struct VoiceDetectionAudioInputCatalog: AudioInputDeviceCatalog {
    func availableAudioInputDevices() -> [AudioInputDeviceOption] {
        [AudioInputDeviceOption(id: "mic-1", name: "Test Mic")]
    }
}

private struct VoiceDetectionPermissionClient: PermissionClient {
    func status(for permission: SystemPermission) -> PermissionStatus { .authorized }
    func request(_ permission: SystemPermission) -> PermissionStatus { .authorized }
    func openSettings(for permission: SystemPermission) async {}
}

private struct VoiceDetectionDateProvider: DateProvider {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

private struct VoiceDetectionSystemActivityMonitor: SystemActivityMonitor {
    var currentPauseReasons: Set<ReplayBufferPauseReason> { [] }

    func events() -> AsyncStream<SystemActivityEvent> {
        AsyncStream { $0.finish() }
    }
}

private actor VoiceDetectionRecordingTimeline {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

private actor VoiceDetectionDetectorSpy: VoiceActivityDetecting {
    let timeline: VoiceDetectionRecordingTimeline
    private var continuation: AsyncStream<VoiceActivityDetectorEvent>.Continuation?

    init(timeline: VoiceDetectionRecordingTimeline) {
        self.timeline = timeline
    }

    func start(deviceID: String?) async -> AsyncStream<VoiceActivityDetectorEvent> {
        await timeline.append("start-detector")
        let stream = AsyncStream.makeStream(of: VoiceActivityDetectorEvent.self)
        continuation = stream.continuation
        return stream.stream
    }

    func stop() async {
        await timeline.append("stop-detector")
        continuation?.finish()
        continuation = nil
    }
}

private actor VoiceDetectionNotifierSpy: VoiceRecordingPromptNotifying {
    let timeline: VoiceDetectionRecordingTimeline

    init(timeline: VoiceDetectionRecordingTimeline) {
        self.timeline = timeline
    }

    func authorizationStatus() -> VoiceDetectionAuthorizationStatus { .authorized }
    func requestAuthorization() -> VoiceDetectionAuthorizationStatus { .authorized }
    nonisolated func openSettings() {}
    func postPrompt() async { await timeline.append("post-prompt") }
    func removePrompt() async { await timeline.append("remove-prompt") }
}

private actor VoiceDetectionAudioRecorderSpy: AudioRecorder {
    let timeline: VoiceDetectionRecordingTimeline
    private(set) var requests: [AudioRecordingRequest] = []

    init(timeline: VoiceDetectionRecordingTimeline) {
        self.timeline = timeline
    }

    func startRecording(_ request: AudioRecordingRequest) async {
        requests.append(request)
        await timeline.append("start-recorder")
    }

    func stopRecording() async {}
}
