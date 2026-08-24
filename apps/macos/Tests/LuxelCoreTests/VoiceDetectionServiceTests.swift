import Foundation
import LuxelCore
import Testing

@Suite("Voice detection service")
struct VoiceDetectionServiceTests {
    @Test("eligible detector starts from a fresh stream")
    func eligibleDetectorStartsFromFreshStream() async {
        let service = VoiceDetectionService()

        let effects = await service.reconcile(eligibility: eligible())

        #expect(effects == [.resetDetector, .startDetector(deviceID: "mic-1")])
        #expect(
            await service.runtimeStatus == .listening(microphoneName: "Studio Microphone")
        )
    }

    @Test("less than ten seconds does not prompt and sustained speech prompts once")
    func sustainedSpeechPromptsOnce() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())

        await expectSustainedSpeechPrompt(service, startingAt: 0)
        #expect(await service.handle(positive(at: 10.24)) == [])
        #expect(await service.handle(positive(at: 30)) == [])
    }

    @Test("default policy requires ten seconds of positive evidence")
    func defaultPolicyRequiresTenSeconds() {
        #expect(VoiceDetectionService.Configuration.default.sustainedSpeechDuration == 10)
        #expect(VoiceDetectionService.Configuration.default.candidateWindowDuration == 12)
    }

    @Test("candidate window discards stale positive evidence")
    func candidateWindowDiscardsStaleEvidence() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())

        for index in 0..<39 {
            #expect(
                await service.handle(positive(at: Double(index) * observationFrameDuration)) == [])
        }
        await expectSustainedSpeechPrompt(service, startingAt: 22)
    }

    @Test("dismiss requires cooldown and continuous silence before rearm")
    func dismissRequiresCooldownAndSilenceBeforeRearm() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)

        #expect(
            await service.handlePromptAction(.dismiss, at: date(10)) == [.removePrompt]
        )
        #expect(await service.handle(negative(at: 10)) == [])
        #expect(await service.handle(negative(at: 40)) == [])

        for time in [41.0, 41.256, 41.512, 41.768] {
            #expect(await service.handle(positive(at: time)) == [])
        }

        #expect(await service.handle(negative(at: 250)) == [])
        #expect(await service.handle(negative(at: 310)) == [])
        await expectSustainedSpeechPrompt(service, startingAt: 311)
    }

    @Test("positive evidence interrupts rearm silence")
    func positiveEvidenceInterruptsRearmSilence() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)
        _ = await service.handlePromptAction(.dismiss, at: date(10))

        #expect(await service.handle(negative(at: 260)) == [])
        #expect(await service.handle(positive(at: 280)) == [])
        #expect(await service.handle(negative(at: 290)) == [])
        #expect(await service.handle(negative(at: 310)) == [])

        for time in [311.0, 311.256, 311.512, 311.768] {
            #expect(await service.handle(positive(at: time)) == [])
        }

        #expect(await service.handle(negative(at: 320)) == [])
        #expect(await service.handle(negative(at: 351)) == [])
        await expectSustainedSpeechPrompt(service, startingAt: 352)
    }

    @Test("reset clears candidates and outstanding prompt")
    func resetClearsCandidatesAndPrompt() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)

        #expect(
            await service.reset(for: .queueOverflow) == [.removePrompt, .resetDetector]
        )
        await expectSustainedSpeechPrompt(service, startingAt: 20)
    }

    @Test("eligibility loss removes prompt and stops detector")
    func eligibilityLossStopsDetector() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)

        let effects = await service.reconcile(
            eligibility: eligible(isRecordingLifecycleIdle: false)
        )

        #expect(effects == [.removePrompt, .stopDetector])
        #expect(await service.runtimeStatus == .pausedWhileRecording)
    }

    @Test("device change removes prompt and restarts from fresh state")
    func deviceChangeRestartsDetector() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)

        let effects = await service.reconcile(
            eligibility: eligible(
                microphone: VoiceDetectionMicrophone(deviceID: "mic-2", name: "Desk Mic")
            )
        )

        #expect(
            effects == [
                .removePrompt,
                .stopDetector,
                .resetDetector,
                .startDetector(deviceID: "mic-2")
            ]
        )
        #expect(await service.handle(positive(at: 2)) == [])
    }

    @Test("notification click and explicit action both request recording")
    func notificationClickAndExplicitActionRequestRecording() async {
        let defaultService = VoiceDetectionService()
        _ = await defaultService.reconcile(eligibility: eligible())
        await reachPrompt(defaultService)
        #expect(
            await defaultService.handlePromptAction(.defaultAction, at: date(1))
                == [.removePrompt, .stopDetector, .startRecording]
        )

        let startService = VoiceDetectionService()
        _ = await startService.reconcile(eligibility: eligible())
        await reachPrompt(startService)
        #expect(
            await startService.handlePromptAction(.startRecording, at: date(1))
                == [.removePrompt, .stopDetector, .startRecording]
        )
    }

    @Test("runtime status explains every ineligible state")
    func runtimeStatusExplainsIneligibleStates() {
        #expect(VoiceDetectionEligibility.disabled.runtimeStatus == .off)
        #expect(
            eligible(notificationPermission: .denied).runtimeStatus == .notificationsRequired
        )
        #expect(
            eligible(microphonePermission: .denied).runtimeStatus == .microphoneAccessRequired
        )
        #expect(eligible(microphone: nil).runtimeStatus == .selectedMicrophoneUnavailable)
        #expect(eligible(isModelAvailable: false).runtimeStatus == .unavailable)
        #expect(eligible(isDetectorReady: false).runtimeStatus == .preparing)
        #expect(
            eligible(isRecordingLifecycleIdle: false).runtimeStatus == .pausedWhileRecording
        )
        #expect(eligible(isSessionLocked: true).runtimeStatus == .pausedWhileLocked)
        #expect(eligible(isDisplayAsleep: true).runtimeStatus == .pausedWhileLocked)
    }
}

private func eligible(
    notificationPermission: VoiceDetectionAuthorizationStatus = .authorized,
    microphonePermission: VoiceDetectionAuthorizationStatus = .authorized,
    microphone: VoiceDetectionMicrophone? = VoiceDetectionMicrophone(
        deviceID: "mic-1",
        name: "Studio Microphone"
    ),
    isModelAvailable: Bool = true,
    isDetectorReady: Bool = true,
    isRecordingLifecycleIdle: Bool = true,
    isSessionLocked: Bool = false,
    isDisplayAsleep: Bool = false
) -> VoiceDetectionEligibility {
    VoiceDetectionEligibility(
        isEnabled: true,
        isDisclosureAccepted: true,
        notificationPermission: notificationPermission,
        microphonePermission: microphonePermission,
        microphone: microphone,
        isModelAvailable: isModelAvailable,
        isDetectorReady: isDetectorReady,
        isRecordingLifecycleIdle: isRecordingLifecycleIdle,
        isSessionLocked: isSessionLocked,
        isDisplayAsleep: isDisplayAsleep
    )
}

private func reachPrompt(_ service: VoiceDetectionService) async {
    await expectSustainedSpeechPrompt(service, startingAt: 0)
}

private func expectSustainedSpeechPrompt(
    _ service: VoiceDetectionService,
    startingAt startTime: TimeInterval
) async {
    for index in 0..<39 {
        #expect(
            await service.handle(
                positive(at: startTime + Double(index) * observationFrameDuration)
            ) == []
        )
    }
    #expect(
        await service.handle(
            positive(at: startTime + Double(39) * observationFrameDuration)
        ) == [.postPrompt]
    )
}

private let observationFrameDuration: TimeInterval = 0.256

private func positive(at time: TimeInterval) -> VoiceActivityDetectorEvent {
    .observation(
        VoiceActivityObservation(probability: 0.9, observedAt: date(time))
    )
}

private func negative(at time: TimeInterval) -> VoiceActivityDetectorEvent {
    .observation(
        VoiceActivityObservation(probability: 0.1, observedAt: date(time))
    )
}

private func date(_ time: TimeInterval) -> Date {
    Date(timeIntervalSince1970: time)
}
