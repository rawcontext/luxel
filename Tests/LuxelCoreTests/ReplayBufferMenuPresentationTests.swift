import LuxelCore
import Testing

@Suite("Replay buffer menu presentation")
struct ReplayBufferMenuPresentationTests {
    @Test("missing configuration hides replay buffer menu")
    func missingConfigurationHidesReplayBufferMenu() {
        let presentation = ReplayBufferMenuPresentation(configuration: nil)

        #expect(!presentation.isVisible)
        #expect(presentation.statusText == "Replay Buffer Off")
        #expect(presentation.statusDetail == "Enable in Settings")
        #expect(presentation.clipActionTitle == "Clip Replay Buffer")
        #expect(!presentation.canClip)
        #expect(!presentation.canPause)
    }

    @Test("configured buffer shows disabled coming soon controls")
    func configuredBufferShowsDisabledComingSoonControls() throws {
        let presentation = ReplayBufferMenuPresentation(
            configuration: try ReplayBufferConfiguration(
                bufferLength: 120,
                source: .displayWithCursor,
                frameRate: FrameRate(24)
            )
        )

        #expect(presentation.isVisible)
        #expect(presentation.statusText == "Replay Buffer Engine Coming Soon")
        #expect(presentation.statusDetail == "2 Minutes · 24 FPS")
        #expect(presentation.clipActionTitle == "Clip Last 2 Minutes")
        #expect(presentation.pauseActionTitle == "Pause Replay Buffer")
        #expect(!presentation.canClip)
        #expect(!presentation.canPause)
    }

    @Test("engine availability enables replay buffer controls")
    func engineAvailabilityEnablesReplayBufferControls() throws {
        let presentation = ReplayBufferMenuPresentation(
            configuration: try ReplayBufferConfiguration(
                bufferLength: 30,
                source: .displayWithCursor,
                frameRate: FrameRate(30)
            ),
            engineAvailable: true
        )

        #expect(presentation.isVisible)
        #expect(presentation.statusText == "Replay Buffer Ready")
        #expect(presentation.statusDetail == "30 Seconds · 30 FPS")
        #expect(presentation.clipActionTitle == "Clip Last 30 Seconds")
        #expect(presentation.canClip)
        #expect(presentation.canPause)
    }
}
