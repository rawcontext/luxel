import Foundation
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

    @Test("configured buffer shows ready controls while disarmed")
    func configuredBufferShowsReadyControlsWhileDisarmed() throws {
        let presentation = ReplayBufferMenuPresentation(
            configuration: try ReplayBufferConfiguration(
                bufferLength: 120,
                source: .displayWithCursor,
                frameRate: FrameRate(24)
            )
        )

        #expect(presentation.isVisible)
        #expect(presentation.statusText == "Replay Buffer Ready")
        #expect(presentation.statusDetail == "2 Minutes · 24 FPS")
        #expect(presentation.clipActionTitle == "Clip Last 2 Minutes")
        #expect(presentation.pauseActionTitle == "Pause Replay Buffer")
        #expect(!presentation.canClip)
        #expect(!presentation.canPause)
    }

    @Test("buffering state enables replay buffer controls")
    func bufferingStateEnablesReplayBufferControls() throws {
        let since = Date(timeIntervalSince1970: 1_000)
        let presentation = ReplayBufferMenuPresentation(
            configuration: try ReplayBufferConfiguration(
                bufferLength: 30,
                source: .displayWithCursor,
                frameRate: FrameRate(30)
            ),
            state: .buffering(since: since),
            now: since.addingTimeInterval(12)
        )

        #expect(presentation.isVisible)
        #expect(presentation.statusText == "Replay Buffering")
        #expect(presentation.statusDetail == "Buffering for 0:12 · 30 Seconds · 30 FPS")
        #expect(presentation.clipActionTitle == "Clip Last 30 Seconds")
        #expect(presentation.canClip)
        #expect(presentation.canPause)
    }

    @Test("starting state waits for replay buffer initialization")
    func startingStateWaitsForReplayBufferInitialization() throws {
        let since = Date(timeIntervalSince1970: 1_000)
        let presentation = ReplayBufferMenuPresentation(
            configuration: try ReplayBufferConfiguration(
                bufferLength: 30,
                source: .displayWithCursor,
                frameRate: FrameRate(30)
            ),
            state: .starting(since: since),
            now: since.addingTimeInterval(2)
        )

        #expect(presentation.isVisible)
        #expect(presentation.statusText == "Replay Buffering")
        #expect(presentation.statusDetail == "Buffering for 0:02 · 30 Seconds · 30 FPS")
        #expect(!presentation.canClip)
        #expect(!presentation.canPause)
    }

    @Test("paused state offers resume")
    func pausedStateOffersResume() throws {
        let presentation = ReplayBufferMenuPresentation(
            configuration: try ReplayBufferConfiguration(
                bufferLength: 60,
                source: .displayWithCursor,
                frameRate: FrameRate(30)
            ),
            state: .paused(reason: .user)
        )

        #expect(presentation.statusText == "Replay Buffer Paused")
        #expect(presentation.statusDetail == "Paused by You · 1 Minute buffer")
        #expect(presentation.pauseActionTitle == "Resume Replay Buffer")
        #expect(!presentation.canClip)
        #expect(presentation.canPause)
        #expect(presentation.pauseActionIsResume)
    }
}
