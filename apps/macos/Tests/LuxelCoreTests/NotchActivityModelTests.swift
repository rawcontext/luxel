import Foundation
import LuxelCore
import Testing

@Suite("Notch activity models")
struct NotchActivityModelTests {
    @Test("resolver defaults to dormant")
    func resolverDefaultsToDormant() {
        #expect(NotchActivityResolver.resolve([]) == .dormant)
        #expect(NotchActivityResolver.resolve([.dormant, .idleHover]) == .idleHover)
    }

    @Test("resolver prioritizes recording over replay buffering")
    func resolverPrioritizesRecordingOverReplayBuffering() throws {
        let coverage = try NotchReplayBufferCoverage(coveredDuration: 20, requestedDuration: 30)
        let activity = NotchActivityResolver.resolve([
            .replayBuffering(coverage: coverage),
            .recording(elapsed: 12, audioLevel: AudioLevelSample(rms: 0.3, peak: 0.6), muted: false)
        ])

        #expect(
            activity
                == .recording(elapsed: 12, audioLevel: AudioLevelSample(rms: 0.3, peak: 0.6), muted: false))
    }

    @Test("resolver prioritizes export and transient completion above steady recording")
    func resolverPrioritizesExportAndCompletion() throws {
        let exportSnapshot = ExportProgressSnapshot.exporting(format: .gif, progress: 0.45)
        let artifact = NotchArtifact(fileURL: URL(filePath: "/tmp/Luxel.gif"), kind: .export)

        #expect(
            NotchActivityResolver.resolve([
                .recording(elapsed: 30, audioLevel: .silent, muted: true),
                .exporting(snapshot: exportSnapshot)
            ]) == .exporting(snapshot: exportSnapshot)
        )
        #expect(
            NotchActivityResolver.resolve([
                .recording(elapsed: 30, audioLevel: .silent, muted: true),
                .completed(artifact: artifact)
            ]) == .completed(artifact: artifact)
        )
    }

    @Test("error has the highest priority")
    func errorHasHighestPriority() throws {
        let error = try NotchError(
            title: "Screen Recording",
            message: "Permission is required.",
            recoveryAction: .openSettings
        )

        let activity = NotchActivityResolver.resolve([
            .completed(
                artifact: NotchArtifact(fileURL: URL(filePath: "/tmp/Luxel.mp4"), kind: .recording)),
            .error(error)
        ])

        #expect(activity == .error(error))
    }

    @Test("transient activities yield to the previous steady activity")
    func transientActivitiesYieldToPreviousSteadyActivity() throws {
        let completed = NotchActivity.completed(
            artifact: NotchArtifact(fileURL: URL(filePath: "/tmp/Luxel.mp4"), kind: .recording)
        )
        let recording = NotchActivity.recording(elapsed: 42, audioLevel: .silent, muted: false)

        #expect(NotchActivityResolver.yieldTransient(completed, to: recording) == recording)
        #expect(NotchActivityResolver.yieldTransient(recording, to: .dormant) == recording)
        #expect(NotchActivityResolver.yieldTransient(completed, to: completed) == .dormant)
    }

    @Test("replay buffer coverage clamps progress")
    func replayBufferCoverageClampsProgress() throws {
        let coverage = try NotchReplayBufferCoverage(coveredDuration: 90, requestedDuration: 60)

        #expect(coverage.coveredDuration == 60)
        #expect(coverage.requestedDuration == 60)
        #expect(coverage.progress == 1)

        #expect(throws: NotchActivityError.invalidReplayCoverage) {
            _ = try NotchReplayBufferCoverage(coveredDuration: -1, requestedDuration: 60)
        }
        #expect(throws: NotchActivityError.invalidReplayCoverage) {
            _ = try NotchReplayBufferCoverage(coveredDuration: 10, requestedDuration: 0)
        }
    }

    @Test("error trims and validates visible text")
    func errorTrimsAndValidatesVisibleText() throws {
        let error = try NotchError(title: "  Export Failed ", message: " Disk is full. ")

        #expect(error.title == "Export Failed")
        #expect(error.message == "Disk is full.")

        #expect(throws: NotchActivityError.emptyErrorText) {
            _ = try NotchError(title: "", message: "Permission required")
        }
        #expect(throws: NotchActivityError.emptyErrorText) {
            _ = try NotchError(title: "Permission", message: "  ")
        }
    }

    @Test("now playing progress clamps elapsed time")
    func nowPlayingProgressClampsElapsedTime() throws {
        let nowPlaying = try NotchNowPlayingSnapshot(elapsed: 120, duration: 60)

        #expect(nowPlaying.elapsed == 60)
        #expect(nowPlaying.progress == 1)

        #expect(throws: NotchActivityError.invalidPlaybackTime) {
            _ = try NotchNowPlayingSnapshot(elapsed: .nan, duration: 60)
        }
        #expect(throws: NotchActivityError.invalidPlaybackTime) {
            _ = try NotchNowPlayingSnapshot(elapsed: 10, duration: 0)
        }
    }
}
