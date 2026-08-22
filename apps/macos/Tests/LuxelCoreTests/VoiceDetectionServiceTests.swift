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

    @Test("one positive frame does not prompt and sustained speech prompts once")
    func sustainedSpeechPromptsOnce() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())

        #expect(await service.handle(positive(at: 0)) == [])
        #expect(await service.handle(positive(at: 0.256)) == [])
        #expect(await service.handle(positive(at: 0.512)) == [])
        #expect(await service.handle(positive(at: 0.768)) == [.postPrompt])
        #expect(await service.handle(positive(at: 1.024)) == [])
        #expect(await service.handle(positive(at: 30)) == [])
    }

    @Test("candidate window discards stale positive evidence")
    func candidateWindowDiscardsStaleEvidence() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())

        #expect(await service.handle(positive(at: 0)) == [])
        #expect(await service.handle(positive(at: 0.256)) == [])
        #expect(await service.handle(positive(at: 2)) == [])
        #expect(await service.handle(positive(at: 2.256)) == [])
        #expect(await service.handle(positive(at: 2.512)) == [])
        #expect(await service.handle(positive(at: 2.768)) == [.postPrompt])
    }

    @Test("dismiss requires cooldown and continuous silence before rearm")
    func dismissRequiresCooldownAndSilenceBeforeRearm() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)

        #expect(
            await service.handlePromptAction(.dismiss, at: date(1)) == [.removePrompt]
        )
        #expect(await service.handle(negative(at: 10)) == [])
        #expect(await service.handle(negative(at: 40)) == [])

        for time in [41.0, 41.256, 41.512, 41.768] {
            #expect(await service.handle(positive(at: time)) == [])
        }

        #expect(await service.handle(negative(at: 250)) == [])
        #expect(await service.handle(negative(at: 301)) == [])
        #expect(await service.handle(positive(at: 302)) == [])
        #expect(await service.handle(positive(at: 302.256)) == [])
        #expect(await service.handle(positive(at: 302.512)) == [])
        #expect(await service.handle(positive(at: 302.768)) == [.postPrompt])
    }

    @Test("positive evidence interrupts rearm silence")
    func positiveEvidenceInterruptsRearmSilence() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)
        _ = await service.handlePromptAction(.dismiss, at: date(1))

        #expect(await service.handle(negative(at: 260)) == [])
        #expect(await service.handle(positive(at: 280)) == [])
        #expect(await service.handle(negative(at: 290)) == [])
        #expect(await service.handle(negative(at: 310)) == [])

        for time in [311.0, 311.256, 311.512, 311.768] {
            #expect(await service.handle(positive(at: time)) == [])
        }

        #expect(await service.handle(negative(at: 320)) == [])
        #expect(await service.handle(negative(at: 351)) == [])
        #expect(await service.handle(positive(at: 352)) == [])
        #expect(await service.handle(positive(at: 352.256)) == [])
        #expect(await service.handle(positive(at: 352.512)) == [])
        #expect(await service.handle(positive(at: 352.768)) == [.postPrompt])
    }

    @Test("reset clears candidates and outstanding prompt")
    func resetClearsCandidatesAndPrompt() async {
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: eligible())
        await reachPrompt(service)

        #expect(
            await service.reset(for: .queueOverflow) == [.removePrompt, .resetDetector]
        )
        #expect(await service.handle(positive(at: 2)) == [])
        #expect(await service.handle(positive(at: 2.256)) == [])
        #expect(await service.handle(positive(at: 2.512)) == [])
        #expect(await service.handle(positive(at: 2.768)) == [.postPrompt])
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

    @Test("only explicit start action requests recording")
    func onlyExplicitStartRequestsRecording() async {
        let defaultService = VoiceDetectionService()
        _ = await defaultService.reconcile(eligibility: eligible())
        await reachPrompt(defaultService)
        #expect(
            await defaultService.handlePromptAction(.defaultAction, at: date(1))
                == [.activateApplication]
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
    _ = await service.handle(positive(at: 0))
    _ = await service.handle(positive(at: 0.256))
    _ = await service.handle(positive(at: 0.512))
    _ = await service.handle(positive(at: 0.768))
}

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
