import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func makeRecordingRequest(
        target: CaptureTarget,
        pixelSize: PixelSize,
        captureKind: QuickCaptureKind,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil
    ) throws -> (request: RecordingRequest, noticeMessage: String?) {
        let frameRate = try FrameRate(settings.record60FPS ? 60 : 30)
        let outputFileURL = try nextRecordingFileURL(now: Date(), directory: outputDirectory)
        let resolvedAudio = resolveRecordingAudioMode()
        let schedule = try recordingSchedule(
            countdownSeconds: countdownSeconds,
            maxRecordedDuration: settings.lastStopAfter
        )
        let usesBakedCursor = settings.cursorMode == .baked

        return (
            RecordingRequest(
                target: target,
                outputFileURL: outputFileURL,
                pixelSize: pixelSize,
                frameRate: frameRate,
                showCursor: usesBakedCursor,
                highlightClicks: usesBakedCursor && settings.highlightClicks,
                captureKeystrokes: settings.keystrokeOverlayEnabled,
                camera: settings.cameraRecordingOptions,
                audio: resolvedAudio.mode,
                videoCodec: .h264,
                captureKind: captureKind,
                schedule: schedule
            ),
            resolvedAudio.noticeMessage
        )
    }

    func recordingSchedule(
        countdownSeconds: Int?,
        maxRecordedDuration: TimeInterval?
    ) throws -> RecordingSchedule? {
        let countdown = countdownSeconds.flatMap { seconds -> TimeInterval? in
            seconds > 0 ? TimeInterval(seconds) : nil
        }

        guard countdown != nil || maxRecordedDuration != nil else {
            return nil
        }

        return try RecordingSchedule(
            countdown: countdown,
            maxRecordedDuration: maxRecordedDuration
        )
    }

    func makeAudioRecordingRequest() throws -> (request: AudioRecordingRequest, noticeMessage: String?) {
        let resolution = resolveSelectedAudioInputDevice()

        return (
            try AudioRecordingRequest(
                outputFileURL: try nextAudioRecordingFileURL(now: Date(), format: settings.audioOnlyFormat),
                audio: .microphone(deviceID: resolution.microphoneDeviceID),
                format: settings.audioOnlyFormat
            ),
            resolution.fallbackMessage
        )
    }

    func rememberLastCapture(from request: RecordingRequest, capturedAt: Date) {
        guard settings.rememberLastCapture else {
            return
        }

        settings.lastCaptureMemory = LastCaptureMemory(request: request, capturedAt: capturedAt)
        saveSettings()
    }

    private func resolveRecordingAudioMode() -> (mode: RecordingAudioMode, noticeMessage: String?) {
        guard settings.recordAudio else {
            return (.none, nil)
        }

        let resolution = resolveSelectedAudioInputDevice()

        return (
            .systemAndMicrophone(deviceID: resolution.microphoneDeviceID),
            resolution.fallbackMessage
        )
    }

    func nextRecordingFileURL(now: Date, directory: URL? = nil) throws -> URL {
        let recordingName = RecordingName.timestamped(now: now).value
        return (directory ?? settings.recordingsDirectory)
            .appending(path: recordingName)
            .appendingPathExtension("mp4")
    }

    func recordingOutputFinalizationPlan(
        for finalFileURL: URL
    ) throws -> RecordingOutputFinalizationPlan {
        let stagingDirectory = LuxelCompositionRoot.recordingStagingDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        return RecordingOutputFinalizationPlan(
            stagingFileURL: stagingDirectory.appending(path: finalFileURL.lastPathComponent),
            finalFileURL: finalFileURL,
            finalDirectoryBookmark: finalDirectoryBookmark(for: finalFileURL)
        )
    }

    private func finalDirectoryBookmark(for finalFileURL: URL) -> BookmarkedDirectory? {
        guard finalFileURL.deletingLastPathComponent().standardizedFileURL == settings.recordingsDirectory.standardizedFileURL else {
            return nil
        }

        return settings.recordingsDirectoryBookmark
    }

    private func nextAudioRecordingFileURL(now: Date, format: AudioRecordingFormat) throws -> URL {
        let recordingName = RecordingName.timestamped(now: now).value
        return settings.recordingsDirectory
            .appending(path: recordingName)
            .appendingPathExtension(format.fileExtension)
    }
}
