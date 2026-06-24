import Foundation
import LuxelCore
import OSLog

private let luxelRecordingLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "media.luxel.app",
    category: "Recording"
)

@MainActor
extension LuxelMenuModel {
    func startRecording(
        from draft: CaptureSelectionDraft,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        do {
            let target = try draft.captureTarget
            let pixelSize = try draft.pixelSize
            await startRecording(
                target: target,
                pixelSize: pixelSize,
                captureKind: .standard,
                countdownSeconds: cropperCountdownSeconds,
                notchRecordingActionID: notchRecordingActionID
            )
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func startQuickRecording(
        from draft: CaptureSelectionDraft,
        presetID: UUID,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        do {
            let target = try draft.captureTarget
            let pixelSize = try draft.pixelSize
            await startRecording(
                target: target,
                pixelSize: pixelSize,
                captureKind: .quick(presetID: presetID),
                countdownSeconds: cropperCountdownSeconds,
                notchRecordingActionID: notchRecordingActionID
            )
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func startRecordingFromSelectedTarget() async {
        guard let selectedCaptureTarget else {
            recordingState = .failed("No capture target selected")
            return
        }

        let latencySpan = LuxelRecordingLatencyTelemetry.begin(
            entryPoint: .recordMenuButton,
            target: selectedCaptureTarget.target
        )
        await startRecording(
            target: selectedCaptureTarget.target,
            pixelSize: selectedCaptureTarget.pixelSize,
            captureKind: .standard,
            latencySpan: latencySpan
        )
    }

    func startFullscreenRecording(
        entryPoint: RecordingStartEntryPoint = .recordFullscreenShortcut,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        guard let displayTarget = fullscreenCaptureTarget else {
            recordingState = .failed("No display target available")
            return
        }

        let latencySpan = LuxelRecordingLatencyTelemetry.begin(
            entryPoint: entryPoint,
            target: displayTarget.target
        )
        await startRecording(
            target: displayTarget.target,
            pixelSize: displayTarget.pixelSize,
            captureKind: .standard,
            latencySpan: latencySpan,
            notchRecordingActionID: notchRecordingActionID
        )
    }

    func startActiveWindowRecording(
        entryPoint: RecordingStartEntryPoint = .recordActiveWindowShortcut,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        guard canSelectArea else {
            recordingState = .failed("No active window target available")
            return
        }

        let latencySpan = LuxelRecordingLatencyTelemetry.begin(entryPoint: entryPoint)
        await refreshCaptureTargets()

        guard
            let windowTarget = activeWindowCaptureTargetResolver.resolve(
                from: captureTargets,
                orderedWindowIDs: activeWindowCatalog.orderedActiveWindowIDs()
            )
        else {
            recordingState = .failed("No active window target available")
            LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "no-active-window-target")
            return
        }

        await startRecording(
            target: windowTarget.target,
            pixelSize: windowTarget.pixelSize,
            captureKind: .standard,
            latencySpan: latencySpan,
            notchRecordingActionID: notchRecordingActionID
        )
    }

    func startRecordingFromLastCapture(
        entryPoint: RecordingStartEntryPoint = .recordAgainButton
    ) async {
        await startRecordingFromLastCapture(
            captureKind: .standard,
            entryPoint: entryPoint
        )
    }

    func startQuickRecordingFromLastCapture(
        entryPoint: RecordingStartEntryPoint = .quickRecordLastButton
    ) async {
        guard let presetID = settings.quickExportPresetID else {
            recordingState = .failed("No quick export preset selected")
            return
        }

        await startRecordingFromLastCapture(
            captureKind: .quick(presetID: presetID),
            entryPoint: entryPoint
        )
    }

    private func startRecordingFromLastCapture(
        captureKind: QuickCaptureKind,
        entryPoint: RecordingStartEntryPoint,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil
    ) async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        let latencySpan = LuxelRecordingLatencyTelemetry.begin(entryPoint: entryPoint)

        do {
            let request = try lastCaptureRecordingPlanner.recordingRequest(
                from: settings.lastCaptureMemory,
                availableTargets: captureTargets,
                fallbackDisplay: lastCaptureFallbackDisplay,
                outputFileURL: try nextRecordingFileURL(now: Date(), directory: outputDirectory),
                captureKind: captureKind
            )
            let scheduledRequest = try requestByApplyingAutomationCountdown(
                countdownSeconds,
                to: request
            )
            await startRecording(
                recordingRequestWithAvailableSources(scheduledRequest),
                latencySpan: latencySpan
            )
        } catch {
            recordingState = .failed(errorMessage(error))
            LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "request-build-failed")
        }
    }

    func startQuickRecordingFromSelectedTarget() async {
        guard let presetID = settings.quickExportPresetID else {
            recordingState = .failed("No quick export preset selected")
            return
        }

        guard let selectedCaptureTarget else {
            recordingState = .failed("No capture target selected")
            return
        }

        let latencySpan = LuxelRecordingLatencyTelemetry.begin(
            entryPoint: .quickRecordMenuButton,
            target: selectedCaptureTarget.target
        )
        await startRecording(
            target: selectedCaptureTarget.target,
            pixelSize: selectedCaptureTarget.pixelSize,
            captureKind: .quick(presetID: presetID),
            latencySpan: latencySpan
        )
    }

    func startAutomationRecording(
        target: CaptureTarget,
        pixelSize: PixelSize,
        presetID: UUID?,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil
    ) async {
        let captureKind = presetID.map(QuickCaptureKind.quick) ?? .standard
        let latencySpan = LuxelRecordingLatencyTelemetry.begin(
            entryPoint: .urlAutomation,
            target: target
        )
        await startRecording(
            target: target,
            pixelSize: pixelSize,
            captureKind: captureKind,
            countdownSeconds: countdownSeconds,
            outputDirectory: outputDirectory,
            latencySpan: latencySpan
        )
    }

    func startAutomationRecordingFromLastCapture(
        presetID: UUID?,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil
    ) async {
        let captureKind = presetID.map(QuickCaptureKind.quick) ?? .standard
        await startRecordingFromLastCapture(
            captureKind: captureKind,
            entryPoint: .urlAutomation,
            countdownSeconds: countdownSeconds,
            outputDirectory: outputDirectory
        )
    }

    func startAudioOnlyRecording(notchRecordingActionID: NotchActivityActionID? = nil) async {
        guard canBeginRecordingStart else {
            return
        }

        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil

        guard microphoneStatus == .authorized else {
            recordingState = .failed("Microphone permission is required")
            return
        }

        activeNotchRecordingActionID = notchRecordingActionID
        recordingState = .starting

        do {
            let preparedRequest = try makeAudioRecordingRequest()
            recordingNoticeMessage = preparedRequest.noticeMessage

            let recordingName = preparedRequest.request.outputFileURL
                .deletingPathExtension()
                .lastPathComponent
            let outputPlan = try recordingOutputFinalizationPlan(
                for: preparedRequest.request.outputFileURL
            )
            let activeRecording = try await audioRecordingLifecycleService.startRecording(
                preparedRequest.request,
                name: recordingName,
                outputPlan: outputPlan
            )
            recordingState = .recording(
                activeRecording,
                RecordingMenuClock(startedAt: activeRecording.date)
            )
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    private var cropperCountdownSeconds: Int? {
        settings.defaultCountdown.map(Int.init)
    }

    private func startRecording(
        target: CaptureTarget,
        pixelSize: PixelSize,
        captureKind: QuickCaptureKind,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil,
        latencySpan: RecordingStartLatencySpan? = nil,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        guard canBeginRecordingStart else {
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(
                    latencySpan, reason: "start-already-in-progress")
            }
            return
        }

        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil

        do {
            let preparedRequest = try makeRecordingRequest(
                target: target,
                pixelSize: pixelSize,
                captureKind: captureKind,
                countdownSeconds: countdownSeconds,
                outputDirectory: outputDirectory
            )
            await startRecording(
                preparedRequest.request,
                noticeMessage: preparedRequest.noticeMessage,
                latencySpan: latencySpan,
                notchRecordingActionID: notchRecordingActionID
            )
        } catch {
            recordingState = .failed(errorMessage(error))
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "request-build-failed")
            }
        }
    }

    private func requestByApplyingAutomationCountdown(
        _ countdownSeconds: Int?,
        to request: RecordingRequest
    ) throws -> RecordingRequest {
        guard countdownSeconds != nil else {
            return request
        }

        return try request.replacingSchedule(
            recordingSchedule(
                countdownSeconds: countdownSeconds,
                maxRecordedDuration: request.schedule?.maxRecordedDuration
            ))
    }

    private func startRecording(
        _ request: RecordingRequest,
        noticeMessage: String? = nil,
        latencySpan: RecordingStartLatencySpan? = nil,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        guard canBeginRecordingStart else {
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(
                    latencySpan, reason: "start-already-in-progress")
            }
            return
        }

        recordingNoticeMessage = noticeMessage
        recordingActionErrorMessage = nil
        activeNotchRecordingActionID = notchRecordingActionID
        recordingState = .starting
        setCameraPreviewHoverControlsEnabled(false)

        do {
            await recordingFramePanelController.present(
                for: request,
                availableTargets: captureTargets,
                exclusionRegistry: captureExclusionRegistry
            )

            let recordingName = request.outputFileURL.deletingPathExtension().lastPathComponent
            let outputPlan = try recordingOutputFinalizationPlan(for: request.outputFileURL)
            if let countdown = request.schedule?.countdown, countdown > 0 {
                recordingState = .countingDown(startedAt: Date(), duration: countdown)
            }

            let startTask = Task<ActiveRecording, any Error> {
                try await recordingLifecycleService.startRecording(
                    request,
                    name: recordingName,
                    outputPlan: outputPlan
                )
            }
            recordingStartTask = startTask
            let activeRecording = try await withTaskCancellationHandler {
                try await startTask.value
            } onCancel: {
                startTask.cancel()
            }
            recordingStartTask = nil
            rememberLastCapture(from: request, capturedAt: activeRecording.date)
            recordingState = .recording(
                activeRecording,
                RecordingMenuClock(startedAt: activeRecording.date)
            )
            await presentCameraPreviewForRecording(request)
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishStarted(latencySpan, target: request.target)
            }
        } catch is CancellationError {
            recordingStartTask = nil
            await recordingFramePanelController.close()
            recordingState = .idle
            syncCameraPreviewHoverControls()
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "start-canceled")
            }
        } catch {
            recordingStartTask = nil
            await recordingFramePanelController.close()
            recordingState = .failed(errorMessage(error))
            syncCameraPreviewHoverControls()
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "recorder-start-failed")
            }
        }
    }

    private var canBeginRecordingStart: Bool {
        switch recordingState {
        case .idle, .failed:
            true
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    func stopRecording() async -> RecordingStopAction? {
        luxelRecordingLogger.info(
            """
      Stop recording requested recording_state=\(self.recordingState.loggingDescription, privacy: .public) \
      has_active_recording=\(self.hasActiveRecording, privacy: .public)
      """
        )

        if case .countingDown = recordingState {
            recordingNoticeMessage = nil
            recordingActionErrorMessage = nil
            recordingState = .starting
            recordingStartTask?.cancel()
            luxelRecordingLogger.info("Stop recording cancelled countdown")
            return nil
        }

        let previousRecordingState = recordingState
        let activeRecording = previousRecordingState.activeRecording
        let captureKind = activeRecording?.options.captureKind ?? .standard
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        recordingState = .stopping
        setCameraPreviewHoverControlsEnabled(false)
        luxelRecordingLogger.info(
            """
      Stop recording transitioned to stopping previous_state=\(previousRecordingState.loggingDescription, privacy: .public) \
      active_recording=\(activeRecording?.name ?? "none", privacy: .private) \
      capture_kind=\(captureKind.loggingDescription, privacy: .public)
      """
        )

        do {
            if activeRecording?.options.isAudioOnly == true {
                let recording = try await audioRecordingLifecycleService.stopRecording()
                refreshRecentRecordings()
                recordingState = .idle
                syncCameraPreviewHoverControls()
                luxelRecordingLogger.info(
                    "Audio recording stop completed output=\(recording.fileURL.lastPathComponent, privacy: .private)"
                )
                return .openEditor(recording.fileURL)
            }

            luxelRecordingLogger.info("Stop recording closing camera preview")
            await closeCameraPreviewForRecordingStop()
            luxelRecordingLogger.info("Stop recording camera preview closed")
            luxelRecordingLogger.info("Stop recording stopping screen recorder")
            let recording = try await recordingLifecycleService.stopRecording()
            luxelRecordingLogger.info("Stop recording screen recorder stopped")
            luxelRecordingLogger.info("Stop recording closing recording frame")
            await recordingFramePanelController.close()
            luxelRecordingLogger.info("Stop recording recording frame closed")
            luxelRecordingLogger.info("Stop recording closing finished camera preview")
            closeCameraPreviewForFinishedRecording()
            luxelRecordingLogger.info("Stop recording finished camera preview closed")
            refreshRecentRecordings()
            luxelRecordingLogger.info(
                """
        Screen recording stop completed output=\(recording.fileURL.lastPathComponent, privacy: .private) \
        capture_kind=\(captureKind.loggingDescription, privacy: .public)
        """
            )

            switch captureKind {
            case .standard:
                recordingState = .idle
                syncCameraPreviewHoverControls()
                luxelRecordingLogger.info("Stop recording completed action=openEditor")
                return .openEditor(recording.primaryMediaURL)
            case .quick(let presetID):
                let stopAction = await runQuickExport(recording: recording, presetID: presetID)
                syncCameraPreviewHoverControls()
                luxelRecordingLogger.info(
                    "Stop recording completed action=\(stopAction?.loggingDescription ?? "none", privacy: .public)"
                )
                return stopAction
            }
        } catch {
            let message = errorMessage(error)
            let nsError = error as NSError
            recordingActionErrorMessage = message
            if error.isTerminalRecordingStopFailure {
                closeCameraPreviewForFinishedRecording()
                recordingState = .idle
                refreshRecentRecordings()
            } else {
                recordingState = previousRecordingState
            }
            syncCameraPreviewHoverControls()
            luxelRecordingLogger.error(
                """
        Stop recording failed previous_state=\(previousRecordingState.loggingDescription, privacy: .public) \
        restored_state=\(self.recordingState.loggingDescription, privacy: .public) \
        error_domain=\(nsError.domain, privacy: .public) \
        error_code=\(nsError.code, privacy: .public) \
        message=\(message, privacy: .public)
        """
            )
            return nil
        }
    }

    func watchRecordingAutoStops(openRecording: @escaping @MainActor (URL) -> Void) async {
        for await recording in recordingLifecycleService.autoStoppedRecordings {
            await handleAutoStoppedRecording(recording, openRecording: openRecording)
        }
    }

    func pauseOrResumeRecording() async {
        switch recordingState {
        case .recording:
            await pauseRecording()
        case .paused:
            await resumeRecording()
        case .idle, .starting, .countingDown, .pausing, .resuming, .stopping, .exporting, .failed:
            return
        }
    }

    func discardActiveRecording() async {
        let stopAction = await stopRecording()
        let fileURL: URL?

        switch stopAction {
        case .openEditor(let url), .quickExported(let url), .audioRecorded(let url):
            fileURL = url
        case .none:
            fileURL = nil
        }

        guard let fileURL else {
            return
        }

        refreshRecentRecordings()

        guard
            let recording = recentRecordings.first(where: { recording in
                recording.fileURL == fileURL || recording.primaryMediaURL == fileURL
            })
        else {
            return
        }

        do {
            _ = try recordingHistoryService.discardRecording(recording)
            refreshRecentRecordings()
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    private func handleAutoStoppedRecording(
        _ recording: PastRecording,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async {
        guard recordingState.activeRecording?.fileURL == recording.fileURL else {
            refreshRecentRecordings()
            return
        }

        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        recordingState = .stopping
        await recordingFramePanelController.close()
        closeCameraPreviewForFinishedRecording()
        refreshRecentRecordings()

        switch recording.options.captureKind {
        case .standard:
            recordingState = .idle
            syncCameraPreviewHoverControls()
            openRecording(recording.primaryMediaURL)
        case .quick(let presetID):
            _ = await runQuickExport(recording: recording, presetID: presetID)
            syncCameraPreviewHoverControls()
        }
    }

    private func pauseRecording() async {
        guard case .recording(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .pausing(activeRecording, clock)

        do {
            try await recordingLifecycleService.pauseRecording()
            recordingState = .paused(activeRecording, clock.paused(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .recording(activeRecording, clock)
        }
    }

    private func resumeRecording() async {
        guard case .paused(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .resuming(activeRecording, clock)

        do {
            try await recordingLifecycleService.resumeRecording()
            recordingState = .recording(activeRecording, clock.resumed(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .paused(activeRecording, clock)
        }
    }
}

extension Error {
    fileprivate var isTerminalRecordingStopFailure: Bool {
        guard let lifecycleError = self as? RecordingLifecycleError else {
            return false
        }

        if case .outputFinalizationFailed = lifecycleError {
            return true
        }

        return false
    }
}

extension QuickCaptureKind {
    fileprivate var loggingDescription: String {
        switch self {
        case .standard:
            "standard"
        case .quick:
            "quick"
        }
    }
}
