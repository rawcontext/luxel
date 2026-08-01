import LuxelCore
import Testing

func expectDefaultKeystrokeAndFrameRateSettings(
    _ settings: AppSettings,
    loopExports: Bool
) throws {
    #expect(!settings.keystrokeOverlayEnabled)
    #expect(settings.keystrokeLivePreviewEnabled)
    #expect(settings.keystrokeRenderOptions == .standard)
    #expect(settings.pauseKeystrokeCaptureShortcut == "")
    #expect(settings.record60FPS)
    #expect(settings.recordingFrameRate == (try FrameRate(60)))
    #expect(settings.loopExports == loopExports)
}

func expectDefaultCameraAndReplaySettings(_ settings: AppSettings) {
    #expect(settings.cameraDeviceID == nil)
    #expect(settings.cameraSeparateTrack)
    #expect(settings.cameraPreviewStyle == CameraPreviewStyle())
    #expect(settings.cameraPreviewPlacements.isEmpty)
    #expect(settings.cameraRecordingOptions == nil)
    #expect(settings.replayBufferConfiguration == nil)
    #expect(
        settings.replayBufferPreferredBufferLength == ReplayBufferConfiguration.defaults.bufferLength
    )
    #expect(!settings.replayBufferResumeOnLaunch)
    #expect(!settings.replayBufferConsentAccepted)
    #expect(!settings.alwaysShowReplayBufferIsland)
    #expect(settings.replayClipDestination == .editor)
}
