import Foundation
import LuxelTestSupport
import Testing

@testable import LuxelCore

@Suite("Voice detection coordination")
struct VoiceDetectionCoordinatorTests {
    @Test("eligibility starts detection and permission loss stops it")
    func eligibilityLifecycle() async {
        let detector = TestVoiceActivityDetectorSpy()
        let notifier = VoiceRecordingPromptNotifierSpy()
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)

        #expect(
            await coordinator.reconcile(eligibility: eligible())
                == .listening(microphoneName: "Test Mic"))
        #expect(await detector.events == [.start("mic-1")])

        #expect(
            await coordinator.reconcile(
                eligibility: eligible(
                    notificationPermission: .denied
                )) == .notificationsRequired)
        #expect(await detector.events == [.start("mic-1"), .stop])
    }

    @Test("sustained speech posts once and explicit consent stops before returning start")
    func promptAndStartOrdering() async {
        let timeline = VoiceDetectionTimeline()
        let detector = TestVoiceActivityDetectorSpy(
            didStop: { await timeline.append("stop-detector") }
        )
        let notifier = VoiceRecordingPromptNotifierSpy(timeline: timeline)
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)
        _ = await coordinator.reconcile(eligibility: eligible())

        for event in testSustainedSpeechEvents() {
            await coordinator.receive(event)
        }

        #expect(await notifier.postCount == 1)
        #expect(await coordinator.handlePromptAction(.startRecording) == .startRecording)
        #expect(await timeline.events.suffix(2) == ["remove-prompt", "stop-detector"])
    }

    @Test("dismiss and stale recording actions cannot start recording")
    func nonConsentAndStaleActions() async {
        let coordinator = VoiceDetectionCoordinator(
            detector: TestVoiceActivityDetectorSpy(),
            notifier: VoiceRecordingPromptNotifierSpy()
        )
        _ = await coordinator.reconcile(eligibility: eligible())

        #expect(await coordinator.handlePromptAction(.dismiss) == .none)
        #expect(await coordinator.handlePromptAction(.defaultAction) == .activateApplication)
        #expect(await coordinator.handlePromptAction(.startRecording) == .activateApplication)
    }

    @Test("concurrent recording actions consume one outstanding prompt at most once")
    func concurrentRecordingActionsStartAtMostOnce() async {
        let coordinator = VoiceDetectionCoordinator(
            detector: TestVoiceActivityDetectorSpy(),
            notifier: VoiceRecordingPromptNotifierSpy()
        )
        _ = await coordinator.reconcile(eligibility: eligible())
        for event in testSustainedSpeechEvents() {
            await coordinator.receive(event)
        }

        let outcomes = await withTaskGroup(
            of: VoiceDetectionCoordinatorOutcome.self,
            returning: [VoiceDetectionCoordinatorOutcome].self
        ) { group in
            group.addTask {
                await coordinator.handlePromptAction(.startRecording)
            }
            group.addTask {
                await coordinator.handlePromptAction(.defaultAction)
            }

            var outcomes: [VoiceDetectionCoordinatorOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        #expect(outcomes.filter { $0 == .startRecording }.count == 1)
        #expect(outcomes.filter { $0 == .activateApplication }.count == 1)
    }

    @Test("device loss removes an outstanding prompt and stops capture")
    func deviceLoss() async {
        let detector = TestVoiceActivityDetectorSpy()
        let notifier = VoiceRecordingPromptNotifierSpy()
        let coordinator = VoiceDetectionCoordinator(detector: detector, notifier: notifier)
        _ = await coordinator.reconcile(eligibility: eligible())
        for event in testSustainedSpeechEvents() {
            await coordinator.receive(event)
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
