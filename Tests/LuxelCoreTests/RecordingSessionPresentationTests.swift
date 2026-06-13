import LuxelCore
import Testing

@Suite("Recording session presentation")
struct RecordingSessionPresentationTests {
    @Test("idle exposes Luxel menu label and record action availability")
    func idleExposesMenuLabelAndRecordAvailability() {
        let disabled = RecordingSessionPresentation(state: .idle, canStartRecording: false)
        let enabled = RecordingSessionPresentation(state: .idle, canStartRecording: true)

        #expect(disabled.menuBarTitle == "Luxel")
        #expect(disabled.menuBarSystemImage == "record.circle")
        #expect(disabled.alternateMenuBarSystemImage == nil)
        #expect(!disabled.animatesMenuBarSystemImage)
        #expect(disabled.primaryActionTitle == "Record")
        #expect(disabled.primaryActionSystemImage == "record.circle.fill")
        #expect(!disabled.canUsePrimaryAction)
        #expect(disabled.secondaryActionTitle == nil)
        #expect(enabled.canUsePrimaryAction)
    }

    @Test("recording formats elapsed time with stop and pause actions")
    func recordingFormatsElapsedTimeWithStopAndPauseActions() {
        let presentation = RecordingSessionPresentation(
            state: .recording(elapsed: 102),
            canStartRecording: false
        )

        #expect(presentation.menuBarTitle == "● 1:42")
        #expect(presentation.menuBarSystemImage == "record.circle")
        #expect(presentation.alternateMenuBarSystemImage == "record.circle.fill")
        #expect(presentation.animatesMenuBarSystemImage)
        #expect(presentation.accessibilityLabel == "Luxel recording, elapsed 1:42")
        #expect(presentation.primaryActionTitle == "Stop")
        #expect(presentation.primaryActionSystemImage == "stop.circle.fill")
        #expect(presentation.canUsePrimaryAction)
        #expect(presentation.secondaryActionTitle == "Pause")
        #expect(presentation.secondaryActionSystemImage == "pause.circle")
        #expect(presentation.canUseSecondaryAction)
    }

    @Test("elapsed label can collapse to glyph only")
    func elapsedLabelCanCollapseToGlyphOnly() {
        let presentation = RecordingSessionPresentation(
            state: .recording(elapsed: 102),
            canStartRecording: false,
            showElapsedTimeInMenuBar: false
        )

        #expect(presentation.menuBarTitle == "●")
        #expect(presentation.accessibilityLabel == "Luxel recording")
    }

    @Test("recording timer shows remaining time in menu bar")
    func recordingTimerShowsRemainingTimeInMenuBar() {
        let presentation = RecordingSessionPresentation(
            state: .recording(elapsed: 18, remaining: 42),
            canStartRecording: false
        )

        #expect(presentation.menuBarTitle == "● −0:42")
        #expect(presentation.accessibilityLabel == "Luxel recording, remaining 0:42")
    }

    @Test("paused uses frozen pause glyph and resume action")
    func pausedUsesFrozenPauseGlyphAndResumeAction() {
        let presentation = RecordingSessionPresentation(
            state: .paused(elapsed: 3723),
            canStartRecording: false
        )

        #expect(presentation.menuBarTitle == "‖ 1:02:03")
        #expect(presentation.menuBarSystemImage == "pause.circle.fill")
        #expect(!presentation.animatesMenuBarSystemImage)
        #expect(presentation.primaryActionTitle == "Stop")
        #expect(presentation.canUsePrimaryAction)
        #expect(presentation.secondaryActionTitle == "Resume")
        #expect(presentation.secondaryActionSystemImage == "play.circle")
        #expect(presentation.canUseSecondaryAction)
    }

    @Test("paused timer freezes remaining time in menu bar")
    func pausedTimerFreezesRemainingTimeInMenuBar() {
        let presentation = RecordingSessionPresentation(
            state: .paused(elapsed: 12, remaining: 18),
            canStartRecording: false
        )

        #expect(presentation.menuBarTitle == "‖ −0:18")
        #expect(presentation.accessibilityLabel == "Luxel recording paused, remaining 0:18")
    }

    @Test("transitional states disable actions")
    func transitionalStatesDisableActions() {
        let starting = RecordingSessionPresentation(state: .starting, canStartRecording: true)
        let pausing = RecordingSessionPresentation(state: .pausing(elapsed: 4), canStartRecording: false)
        let resuming = RecordingSessionPresentation(state: .resuming(elapsed: 5), canStartRecording: false)
        let stopping = RecordingSessionPresentation(state: .stopping, canStartRecording: false)

        #expect(starting.menuBarTitle == "Starting")
        #expect(!starting.canUsePrimaryAction)
        #expect(pausing.secondaryActionTitle == "Pausing")
        #expect(!pausing.canUsePrimaryAction)
        #expect(!pausing.canUseSecondaryAction)
        #expect(resuming.secondaryActionTitle == "Resuming")
        #expect(!resuming.canUsePrimaryAction)
        #expect(!resuming.canUseSecondaryAction)
        #expect(stopping.menuBarTitle == "Stopping")
        #expect(!stopping.canUsePrimaryAction)
    }

    @Test("exporting surfaces progress in menu label")
    func exportingSurfacesProgressInMenuLabel() {
        let presentation = RecordingSessionPresentation(
            state: .exporting(.exporting(format: .gif, progress: 0.426)),
            canStartRecording: false
        )

        #expect(presentation.menuBarTitle == "43%")
        #expect(presentation.menuBarSystemImage == "square.and.arrow.up")
        #expect(presentation.accessibilityLabel == "Luxel exporting, 43% complete")
        #expect(presentation.statusMessage == "Exporting GIF")
        #expect(!presentation.canUsePrimaryAction)
    }

    @Test("failed state keeps error message and can restart when target is ready")
    func failedStateKeepsErrorMessageAndCanRestartWhenTargetIsReady() {
        let presentation = RecordingSessionPresentation(
            state: .failed("Screen recording permission is missing"),
            canStartRecording: true
        )

        #expect(presentation.menuBarTitle == "Luxel")
        #expect(presentation.menuBarSystemImage == "exclamationmark.triangle.fill")
        #expect(presentation.statusMessage == "Screen recording permission is missing")
        #expect(presentation.canUsePrimaryAction)
    }
}
