import Foundation
import LuxelCore
import Testing

@Suite("Notch activity presentation")
struct NotchActivityPresentationTests {
    @Test("idle hover exposes quick actions")
    func idleHoverExposesQuickActions() {
        let viewModel = NotchActivityPresentation.viewModel(for: .idleHover)

        #expect(viewModel.collapsedTitle == "Luxel")
        #expect(viewModel.expandedTitle == "Luxel")
        #expect(viewModel.actions.map(\.id) == [
            .recordFullscreen,
            .recordArea,
            .screenshot,
            .openSettings
        ])
        #expect(viewModel.actions.map(\.systemImage) == [
            "rectangle.dashed",
            "viewfinder",
            "camera",
            "gearshape"
        ])
    }

    @Test("arming exposes countdown and cancel action")
    func armingExposesCountdownAndCancelAction() {
        let viewModel = NotchActivityPresentation.viewModel(for: .arming(remaining: 3.2))

        #expect(viewModel.collapsedTitle == "4 s")
        #expect(viewModel.expandedTitle == "Recording starts in 4 s")
        #expect(viewModel.actions == [
            NotchActivityActionDescriptor(
                id: .cancel,
                title: "Cancel",
                systemImage: "xmark.circle.fill",
                role: .destructive
            )
        ])
    }

    @Test("recording mirrors session timer and exposes controls")
    func recordingMirrorsSessionTimerAndExposesControls() {
        let activity = NotchActivity.recording(
            elapsed: 102.8,
            audioLevel: AudioLevelSample(rms: 0.3, peak: 0.65),
            muted: false
        )
        let session = RecordingSessionPresentation(
            state: .recording(elapsed: 102.8),
            canStartRecording: true
        )

        let viewModel = NotchActivityPresentation.viewModel(for: activity)

        #expect(viewModel.collapsedTitle == session.menuBarTitle)
        #expect(viewModel.expandedDetail == "Elapsed 1:42")
        #expect(viewModel.leadingEarText == "1:42")
        #expect(viewModel.trailingEarText == "Audio 65%")
        #expect(viewModel.audioLevel == AudioLevelSample(rms: 0.3, peak: 0.65))
        #expect(viewModel.actions.map(\.id) == [
            .stopRecording,
            .recordArea,
            .screenshot,
            .openSettings
        ])
        #expect(viewModel.actions.map(\.systemImage) == [
            "stop.fill",
            "viewfinder",
            "camera",
            "gearshape"
        ])
    }

    @Test("recording replaces the initiating notch action with stop")
    func recordingReplacesTheInitiatingNotchActionWithStop() {
        let activity = NotchActivity.recording(
            elapsed: 12,
            audioLevel: AudioLevelSample(rms: 0.2, peak: 0.4),
            muted: false
        )

        let viewModel = NotchActivityPresentation.viewModel(
            for: activity,
            recordingActionToReplace: .recordArea
        )

        #expect(viewModel.actions.map(\.id) == [
            .recordFullscreen,
            .stopRecording,
            .screenshot,
            .openSettings
        ])
        #expect(viewModel.actions.map(\.systemImage) == [
            "rectangle.dashed",
            "stop.fill",
            "camera",
            "gearshape"
        ])
    }

    @Test("muted recording hides audio level")
    func mutedRecordingHidesAudioLevel() {
        let viewModel = NotchActivityPresentation.viewModel(
            for: .recording(elapsed: 5, audioLevel: AudioLevelSample(rms: 1, peak: 1), muted: true)
        )

        #expect(viewModel.audioLevel == nil)
        #expect(viewModel.trailingEarText == "Muted")
        #expect(viewModel.actions.map(\.id) == [.stopRecording, .recordArea, .screenshot, .openSettings])
    }

    @Test("paused mirrors session timer and exposes resume stop discard")
    func pausedMirrorsSessionTimerAndExposesResumeStopDiscard() {
        let session = RecordingSessionPresentation(
            state: .paused(elapsed: 3_722),
            canStartRecording: true
        )
        let viewModel = NotchActivityPresentation.viewModel(for: .paused(elapsed: 3_722))

        #expect(viewModel.collapsedTitle == session.menuBarTitle)
        #expect(viewModel.expandedDetail == "Paused at 1:02:02")
        #expect(viewModel.actions.map(\.id) == [.stopRecording, .recordArea, .screenshot, .openSettings])
    }

    @Test("replay buffering exposes coverage progress and actions")
    func replayBufferingExposesCoverageProgressAndActions() throws {
        let coverage = try NotchReplayBufferCoverage(coveredDuration: 45, requestedDuration: 60)

        let viewModel = NotchActivityPresentation.viewModel(for: .replayBuffering(coverage: coverage))

        #expect(viewModel.collapsedTitle == "Buffer 75%")
        #expect(viewModel.expandedDetail == "45s ready")
        #expect(viewModel.progress == 0.75)
        #expect(viewModel.actions.map(\.id) == [.clipReplay, .pauseReplayBuffer])
    }

    @Test("exporting mirrors export progress")
    func exportingMirrorsExportProgress() {
        let snapshot = ExportProgressSnapshot.exporting(format: .gif, progress: 0.456)
        let session = RecordingSessionPresentation(
            state: .exporting(snapshot),
            canStartRecording: true
        )

        let viewModel = NotchActivityPresentation.viewModel(for: .exporting(snapshot: snapshot))

        #expect(viewModel.collapsedTitle == session.menuBarTitle)
        #expect(viewModel.expandedTitle == "Exporting GIF")
        #expect(viewModel.expandedDetail == "46% complete")
        #expect(viewModel.progress == snapshot.progress)
        #expect(viewModel.actions.map(\.id) == [.cancelExport])
    }

    @Test("completed and screenshot activities carry artifact actions")
    func completedAndScreenshotActivitiesCarryArtifactActions() {
        let export = NotchArtifact(fileURL: URL(filePath: "/tmp/Luxel.gif"), kind: .export)
        let screenshot = NotchArtifact(fileURL: URL(filePath: "/tmp/Luxel.png"), kind: .screenshot)

        let completed = NotchActivityPresentation.viewModel(for: .completed(artifact: export))
        let captured = NotchActivityPresentation.viewModel(for: .screenshotCaptured(artifact: screenshot))

        #expect(completed.expandedTitle == "Export Ready")
        #expect(completed.artifact == export)
        #expect(completed.actions.map(\.id) == [.reveal, .copy, .openInEditor])
        #expect(captured.expandedTitle == "Screenshot Captured")
        #expect(captured.artifact == screenshot)
        #expect(captured.actions.map(\.id) == [.copy, .save, .openInPreview])
    }

    @Test("errors expose matching recovery action")
    func errorsExposeMatchingRecoveryAction() throws {
        let error = try NotchError(
            title: "Screen Recording",
            message: "Permission is required.",
            recoveryAction: .openSettings
        )

        let viewModel = NotchActivityPresentation.viewModel(for: .error(error))

        #expect(viewModel.collapsedTitle == "Error")
        #expect(viewModel.expandedTitle == "Screen Recording")
        #expect(viewModel.expandedDetail == "Permission is required.")
        #expect(viewModel.actions == [
            NotchActivityActionDescriptor(
                id: .openSettings,
                title: "Open Settings",
                systemImage: "gear",
                role: .primary
            )
        ])
    }

    @Test("now playing exposes preview progress")
    func nowPlayingExposesPreviewProgress() throws {
        let snapshot = try NotchNowPlayingSnapshot(elapsed: 45, duration: 90)

        let viewModel = NotchActivityPresentation.viewModel(for: .nowPlaying(snapshot))

        #expect(viewModel.collapsedTitle == "0:45")
        #expect(viewModel.expandedDetail == "0:45 of 1:30")
        #expect(viewModel.progress == 0.5)
    }
}
