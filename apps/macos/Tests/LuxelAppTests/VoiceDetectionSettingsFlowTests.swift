import Foundation
import LuxelTestSupport
import Testing

@testable import LuxelApp
@testable import LuxelCore

@Suite("Voice detection settings flow")
@MainActor
struct VoiceDetectionSettingsFlowTests {
    @Test("cancel keeps first-use intent and disclosure disabled")
    func disclosureCancel() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }

        await fixture.model.cancelVoiceDetectionDisclosure()

        #expect(!fixture.model.settings.speechDetectionPromptsEnabled)
        #expect(!fixture.model.settings.speechDetectionDisclosureAccepted)
    }

    @Test("accept saves intent before requesting notifications and microphone")
    func disclosureAcceptanceOrder() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }

        await fixture.model.approveVoiceDetectionDisclosure()

        #expect(
            fixture.timeline.events == [
                "save-settings", "request-notifications", "request-microphone"
            ])
        #expect(fixture.model.settings.speechDetectionPromptsEnabled)
        #expect(fixture.model.settings.speechDetectionDisclosureAccepted)
        #expect(fixture.model.voiceDetectionStatus == .listening(microphoneName: "Test Mic"))
    }

    @Test("microphone denial preserves intent and opens privacy settings for recovery")
    func microphoneDenialRecovery() async throws {
        let fixture = try makeFixture(microphoneStatus: .denied)
        defer { fixture.removeTemporaryFiles() }

        await fixture.model.approveVoiceDetectionDisclosure()
        #expect(fixture.model.settings.speechDetectionPromptsEnabled)
        #expect(fixture.model.voiceDetectionStatus == .microphoneAccessRequired)

        await fixture.model.recoverVoiceDetectionMicrophoneAccess()
        #expect(fixture.timeline.events.last == "open-microphone-settings")
    }

    @Test("notification denial preserves intent and opens notification settings for recovery")
    func notificationDenialRecovery() async throws {
        let fixture = try makeFixture(notificationStatus: .denied)
        defer { fixture.removeTemporaryFiles() }

        await fixture.model.approveVoiceDetectionDisclosure()
        #expect(fixture.model.settings.speechDetectionPromptsEnabled)
        #expect(fixture.model.voiceDetectionStatus == .notificationsRequired)

        await fixture.model.recoverVoiceDetectionNotificationAccess()
        #expect(fixture.timeline.events.last == "open-notification-settings")
    }

    @Test("device change resets and restarts detection on the explicit microphone")
    func selectedDeviceChange() async throws {
        let fixture = try makeFixture(isEnabled: true)
        defer { fixture.removeTemporaryFiles() }

        await fixture.model.refreshPermissions()
        await fixture.model.reconcileVoiceDetection()
        fixture.model.settings.audioInputDeviceID = "mic-2"
        fixture.model.settings.audioInputDeviceName = "Second Mic"
        await fixture.model.reconcileVoiceDetection()

        #expect(
            await fixture.detector.events == [
                .start("mic-1"), .stop, .start("mic-2")
            ])
    }

    @Test("disablement stops capture and removes an outstanding prompt")
    func disablement() async throws {
        let fixture = try makeFixture(isEnabled: true)
        defer { fixture.removeTemporaryFiles() }
        await fixture.model.refreshPermissions()
        await fixture.model.reconcileVoiceDetection()
        for event in testSustainedSpeechEvents() {
            await fixture.coordinator.receive(event)
        }

        await fixture.model.disableVoiceDetectionPrompts()

        #expect(!fixture.model.settings.speechDetectionPromptsEnabled)
        #expect(fixture.model.voiceDetectionStatus == .off)
        #expect(await fixture.detector.events.last == .stop)
        #expect(fixture.notifier.removeCount == 1)
    }

    private func makeFixture(
        isEnabled: Bool = false,
        microphoneStatus: PermissionStatus = .authorized,
        notificationStatus: VoiceDetectionAuthorizationStatus = .authorized
    ) throws -> VoiceDetectionSettingsFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VoiceDetectionSettingsFlowTests-\(UUID().uuidString)")
        try createTestVoiceDetectionModelDirectory(at: root)
        var settings = AppSettings.defaults(recordingsDirectory: root.appending(path: "Recordings"))
        settings.speechDetectionPromptsEnabled = isEnabled
        settings.speechDetectionDisclosureAccepted = isEnabled
        settings.audioInputDeviceID = "mic-1"
        settings.audioInputDeviceName = "Test Mic"
        let timeline = VoiceDetectionSettingsTimeline()
        let detector = TestVoiceActivityDetectorSpy()
        let notifier = VoiceDetectionSettingsNotifierSpy(
            status: notificationStatus,
            timeline: timeline
        )
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)
        let model = LuxelMenuModel(
            settingsStore: VoiceDetectionSettingsStoreSpy(settings: settings, timeline: timeline),
            permissionClient: VoiceDetectionSettingsPermissionSpy(
                microphoneStatus: microphoneStatus,
                timeline: timeline
            ),
            audioInputDeviceService: AudioInputDeviceService(
                catalog: VoiceDetectionSettingsAudioCatalog()
            ),
            voiceDetectionCoordinator: coordinator,
            voiceDetectionModelLocator: BundledVoiceActivityModelLocator(resourceURL: root),
            systemActivityMonitor: VoiceDetectionSettingsSystemMonitor()
        )
        return VoiceDetectionSettingsFixture(
            root: root,
            model: model,
            coordinator: coordinator,
            detector: detector,
            notifier: notifier,
            timeline: timeline
        )
    }
}

@MainActor
private struct VoiceDetectionSettingsFixture {
    let root: URL
    let model: LuxelMenuModel
    let coordinator: VoiceDetectionCoordinator
    let detector: TestVoiceActivityDetectorSpy
    let notifier: VoiceDetectionSettingsNotifierSpy
    let timeline: VoiceDetectionSettingsTimeline

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class VoiceDetectionSettingsTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] {
        lock.withLock { storedEvents }
    }

    func append(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

private struct VoiceDetectionSettingsStoreSpy: SettingsStore {
    let settings: AppSettings
    let timeline: VoiceDetectionSettingsTimeline

    func load() throws -> AppSettings { settings }
    func save(_ settings: AppSettings) throws { timeline.append("save-settings") }
}

private struct VoiceDetectionSettingsPermissionSpy: PermissionClient {
    let microphoneStatus: PermissionStatus
    let timeline: VoiceDetectionSettingsTimeline

    func status(for permission: SystemPermission) -> PermissionStatus {
        permission == .microphone ? microphoneStatus : .authorized
    }

    func request(_ permission: SystemPermission) -> PermissionStatus {
        timeline.append("request-microphone")
        return microphoneStatus
    }

    func openSettings(for permission: SystemPermission) {
        timeline.append("open-microphone-settings")
    }
}

private struct VoiceDetectionSettingsAudioCatalog: AudioInputDeviceCatalog {
    func availableAudioInputDevices() -> [AudioInputDeviceOption] {
        [
            AudioInputDeviceOption(id: "mic-1", name: "Test Mic"),
            AudioInputDeviceOption(id: "mic-2", name: "Second Mic")
        ]
    }
}

private struct VoiceDetectionSettingsSystemMonitor: SystemActivityMonitor {
    var currentPauseReasons: Set<ReplayBufferPauseReason> { [] }
    func events() -> AsyncStream<SystemActivityEvent> { AsyncStream { $0.finish() } }
}

private final class VoiceDetectionSettingsNotifierSpy:
    VoiceRecordingPromptNotifying,
    @unchecked Sendable {
    let status: VoiceDetectionAuthorizationStatus
    let timeline: VoiceDetectionSettingsTimeline
    private let lock = NSLock()
    private var storedRemoveCount = 0

    init(status: VoiceDetectionAuthorizationStatus, timeline: VoiceDetectionSettingsTimeline) {
        self.status = status
        self.timeline = timeline
    }

    var removeCount: Int { lock.withLock { storedRemoveCount } }

    func authorizationStatus() -> VoiceDetectionAuthorizationStatus { status }

    func requestAuthorization() -> VoiceDetectionAuthorizationStatus {
        timeline.append("request-notifications")
        return status
    }

    @MainActor
    func openSettings() {
        timeline.append("open-notification-settings")
    }

    func postPrompt() {}

    func removePrompt() {
        lock.withLock { storedRemoveCount += 1 }
    }
}
