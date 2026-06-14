import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func makeRecordingRequest(
        target: CaptureTarget,
        pixelSize: PixelSize,
        captureKind: QuickCaptureKind
    ) throws -> (request: RecordingRequest, noticeMessage: String?) {
        let frameRate = try FrameRate(settings.record60FPS ? 60 : 30)
        let outputFileURL = try nextRecordingFileURL(now: Date())
        let resolvedAudio = resolveRecordingAudioMode()
        let schedule = try settings.lastStopAfter.map {
            try RecordingSchedule(maxRecordedDuration: $0)
        }
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
                audio: resolvedAudio.mode,
                videoCodec: .h264,
                captureKind: captureKind,
                schedule: schedule
            ),
            resolvedAudio.noticeMessage
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

    func nextRecordingFileURL(now: Date) throws -> URL {
        try FileManager.default.createDirectory(
            at: settings.recordingsDirectory,
            withIntermediateDirectories: true
        )

        let recordingName = RecordingName.timestamped(now: now).value
        return settings.recordingsDirectory
            .appending(path: recordingName)
            .appendingPathExtension("mp4")
    }

    private func nextAudioRecordingFileURL(now: Date, format: AudioRecordingFormat) throws -> URL {
        try FileManager.default.createDirectory(
            at: settings.recordingsDirectory,
            withIntermediateDirectories: true
        )

        let recordingName = RecordingName.timestamped(now: now).value
        return settings.recordingsDirectory
            .appending(path: recordingName)
            .appendingPathExtension(format.fileExtension)
    }
}
