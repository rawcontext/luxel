import Foundation
@testable import LuxelCore
import Testing

@Suite("Voice detection coordination")
struct VoiceDetectionCoordinatorTests {
    @Test("eligibility starts detection and permission loss stops it")
    func eligibilityLifecycle() async {
        let detector = VoiceActivityDetectorSpy()
        let notifier = VoiceRecordingPromptNotifierSpy()
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)

        #expect(await coordinator.reconcile(eligibility: eligible())
                    == .listening(microphoneName: "Test Mic"))
        #expect(await detector.events == [.start("mic-1")])

        #expect(await coordinator.reconcile(eligibility: eligible(
            notificationPermission: .denied
        )) == .notificationsRequired)
        #expect(await detector.events == [.start("mic-1"), .stop])
    }

    @Test("sustained speech posts once and explicit consent stops before returning start")
    func promptAndStartOrdering() async {
        let timeline = VoiceDetectionTimeline()
        let detector = VoiceActivityDetectorSpy(timeline: timeline)
        let notifier = VoiceRecordingPromptNotifierSpy(timeline: timeline)
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)
        _ = await coordinator.reconcile(eligibility: eligible())

        for index in 0..<4 {
            await coordinator.receive(.observation(
                VoiceActivityObservation(
                    probability: 0.95,
                    observedAt: Date(timeIntervalSince1970: Double(index) * 0.25)
                )
            ))
        }

        #expect(await notifier.postCount == 1)
        #expect(await coordinator.handlePromptAction(.startRecording) == .startRecording)
        #expect(await timeline.events.suffix(2) == ["remove-prompt", "stop-detector"])
    }

    @Test("dismiss, body clicks, and stale recording actions cannot start recording")
    func nonConsentAndStaleActions() async {
        let coordinator = VoiceDetectionCoordinator(
            detector: VoiceActivityDetectorSpy(),
            notifier: VoiceRecordingPromptNotifierSpy()
        )
        _ = await coordinator.reconcile(eligibility: eligible())

        #expect(await coordinator.handlePromptAction(.dismiss) == .none)
        #expect(await coordinator.handlePromptAction(.defaultAction) == .activateApplication)
        #expect(await coordinator.handlePromptAction(.startRecording) == .activateApplication)
    }

    @Test("device loss removes an outstanding prompt and stops capture")
    func deviceLoss() async {
        let detector = VoiceActivityDetectorSpy()
        let notifier = VoiceRecordingPromptNotifierSpy()
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)
        _ = await coordinator.reconcile(eligibility: eligible())
        for index in 0..<4 {
            await coordinator.receive(.observation(
                VoiceActivityObservation(
                    probability: 0.95,
                    observedAt: Date(timeIntervalSince1970: Double(index) * 0.25)
                )
            ))
        }

        _ = await coordinator.reconcile(eligibility: eligible(microphone: nil))

        #expect(await notifier.removeCount == 1)
        #expect(await detector.events.last == .stop)
    }

    private func eligible(
        notificationPermission: VoiceDetectionAuthorizationStatus = .authorized,
        microphone: VoiceDetectionMicrophone? = .init(deviceID: "mic-1", name: "Test Mic")
    ) -> VoiceDetectionEligibility {
        VoiceDetectionEligibility(
            isEnabled: true,
            isDisclosureAccepted: true,
            notificationPermission: notificationPermission,
            microphonePermission: .authorized,
            microphone: microphone,
            isModelAvailable: true,
            isDetectorReady: true,
            isRecordingLifecycleIdle: true,
            isSessionLocked: false,
            isDisplayAsleep: false
        )
    }
}

private actor VoiceActivityDetectorSpy: VoiceActivityDetecting {
    enum Event: Equatable, Sendable {
        case start(String?)
        case stop
    }

    private(set) var events: [Event] = []
    private let timeline: VoiceDetectionTimeline?
    private var continuation: AsyncStream<VoiceActivityDetectorEvent>.Continuation?

    init(timeline: VoiceDetectionTimeline? = nil) {
        self.timeline = timeline
    }

    func start(deviceID: String?) -> AsyncStream<VoiceActivityDetectorEvent> {
        events.append(.start(deviceID))
        let stream = AsyncStream.makeStream(of: VoiceActivityDetectorEvent.self)
        continuation = stream.continuation
        return stream.stream
    }

    func stop() async {
        events.append(.stop)
        await timeline?.append("stop-detector")
        continuation?.finish()
        continuation = nil
    }
}

private actor VoiceRecordingPromptNotifierSpy: VoiceRecordingPromptNotifying {
    private(set) var postCount = 0
    private(set) var removeCount = 0
    private let timeline: VoiceDetectionTimeline?

    init(timeline: VoiceDetectionTimeline? = nil) {
        self.timeline = timeline
    }

    func authorizationStatus() -> VoiceDetectionAuthorizationStatus { .authorized }
    func requestAuthorization() -> VoiceDetectionAuthorizationStatus { .authorized }
    nonisolated func openSettings() {}

    func postPrompt() async {
        postCount += 1
        await timeline?.append("post-prompt")
    }

    func removePrompt() async {
        removeCount += 1
        await timeline?.append("remove-prompt")
    }
}

private actor VoiceDetectionTimeline {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
