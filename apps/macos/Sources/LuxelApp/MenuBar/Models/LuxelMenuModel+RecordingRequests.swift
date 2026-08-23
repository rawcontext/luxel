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
        let frameRate = settings.matchDisplayFrameRate ? FrameRate.fps120 : settings.recordingFrameRate
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
                matchesDisplayFrameRate: settings.matchDisplayFrameRate,
                showCursor: usesBakedCursor,
                highlightClicks: usesBakedCursor && settings.highlightClicks,
                captureKeystrokes: settings.keystrokeOverlayEnabled,
                camera: captureCapabilities.cameraOverlayAvailable
                    ? settings.cameraRecordingOptions : nil,
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

    func makeAudioRecordingRequest() throws -> (
        request: AudioRecordingRequest, noticeMessage: String?
    ) {
        let resolvedAudio = resolveRecordingAudioMode()

        return (
            try AudioRecordingRequest(
                outputFileURL: try nextAudioRecordingFileURL(
                    now: Date(), format: settings.audioOnlyFormat),
                audio: resolvedAudio.mode,
                format: settings.audioOnlyFormat,
                captureKeystrokes: settings.keystrokeOverlayEnabled
            ),
            resolvedAudio.noticeMessage
        )
    }

    func makeSpeechPromptAudioRecordingRequest(
        now: Date = Date()
    ) throws -> AudioRecordingRequest {
        audioInputDevices = audioInputDeviceService.availableInputDevices()
        let selectedID = settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
        guard let selectedDevice = audioInputDevices.first(where: { $0.id == selectedID }) else {
            throw VoiceDetectionRecordingRequestError.selectedMicrophoneUnavailable
        }

        let microphoneDeviceID = selectedDevice.id == AudioInputDeviceID.systemDefault
            ? nil
            : selectedDevice.id
        let audio: RecordingAudioMode =
            settings.recordSystemAudio && captureCapabilities.systemAudioTrackAvailable
            ? .systemAndMicrophone(deviceID: microphoneDeviceID)
            : .microphone(deviceID: microphoneDeviceID)

        return try AudioRecordingRequest(
            outputFileURL: try nextAudioRecordingFileURL(
                now: now,
                format: settings.audioOnlyFormat
            ),
            audio: audio,
            format: settings.audioOnlyFormat,
            captureKeystrokes: false
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
        let recordsSystemAudio = captureCapabilities.systemAudioTrackAvailable
        let recordsMicrophone = captureCapabilities.microphoneTrackAvailable

        switch (recordsSystemAudio, recordsMicrophone) {
        case (true, true):
            let resolution = resolveSelectedAudioInputDevice()
            return (
                .systemAndMicrophone(deviceID: resolution.microphoneDeviceID),
                resolution.fallbackMessage
            )
        case (true, false):
            return (.system, nil)
        case (false, true):
            let resolution = resolveSelectedAudioInputDevice()
            return (
                .microphone(deviceID: resolution.microphoneDeviceID),
                resolution.fallbackMessage
            )
        case (false, false):
            return (.none, nil)
        }
    }

    func recordingRequestWithAvailableSources(_ request: RecordingRequest) -> RecordingRequest {
        RecordingRequest(
            target: request.target,
            outputFileURL: request.outputFileURL,
            pixelSize: request.pixelSize,
            frameRate: request.frameRate,
            matchesDisplayFrameRate: request.matchesDisplayFrameRate,
            showCursor: request.showCursor,
            highlightClicks: request.highlightClicks,
            captureKeystrokes: request.captureKeystrokes,
            camera: captureCapabilities.cameraOverlayAvailable ? request.camera : nil,
            audio: recordingAudioModeWithAvailableSources(request.audio),
            videoCodec: request.videoCodec,
            captureKind: request.captureKind,
            schedule: request.schedule,
            timelapse: request.timelapse
        )
    }

    private func recordingAudioModeWithAvailableSources(_ audio: RecordingAudioMode)
    -> RecordingAudioMode {
        switch (
            audio.capturesSystemAudio && captureCapabilities.systemAudioTrackAvailable,
            audio.capturesMicrophone && captureCapabilities.microphoneTrackAvailable
        ) {
        case (true, true):
            .systemAndMicrophone(deviceID: audio.microphoneDeviceID)
        case (true, false):
            .system
        case (false, true):
            .microphone(deviceID: audio.microphoneDeviceID)
        case (false, false):
            .none
        }
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
        let outputDirectory = finalFileURL.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        let recordingsDirectory = settings.recordingsDirectory
            .standardizedFileURL.resolvingSymlinksInPath()
        if outputDirectory == recordingsDirectory {
            return settings.recordingsDirectoryBookmark
        }
        return settings.commandLineFolderGrants.first { grant in
            let root = grant.directory.url.standardizedFileURL.resolvingSymlinksInPath().path
            return outputDirectory.path == root || outputDirectory.path.hasPrefix(root + "/")
        }?.directory
    }

    func nextAudioRecordingFileURL(now: Date, format: AudioRecordingFormat) throws -> URL {
        let recordingName = RecordingName.timestamped(now: now).value
        return settings.recordingsDirectory
            .appending(path: recordingName)
            .appendingPathExtension(format.fileExtension)
    }
}

enum VoiceDetectionRecordingRequestError: Error, Equatable {
    case selectedMicrophoneUnavailable
}
