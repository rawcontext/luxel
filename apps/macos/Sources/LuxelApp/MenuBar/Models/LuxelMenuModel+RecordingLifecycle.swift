import Foundation
import LuxelCore
import OSLog

@MainActor
extension LuxelMenuModel {
    func startRecording(
        _ request: RecordingRequest,
        noticeMessage: String? = nil,
        latencySpan: RecordingStartLatencySpan? = nil,
        notchRecordingActionID: NotchActivityActionID? = nil
    ) async {
        if request.captureKeystrokes, inputMonitoringStatus != .authorized {
            presentPermissionPrompt(for: .inputMonitoring)
            return
        }
        guard canBeginRecordingStart else {
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(
                    latencySpan, reason: "start-already-in-progress")
            }
            return
        }

        let preparedCamera = await preparingCameraCutoutIfNeeded(for: request)
        let effectiveRequest = preparedCamera.request
        recordingNoticeMessage = preparedCamera.noticeMessage ?? noticeMessage
        recordingActionErrorMessage = nil
        activeNotchRecordingActionID = notchRecordingActionID
        recordingState = .starting
        setCameraPreviewHoverControlsEnabled(false)

        do {
            let activeRecording = try await beginRecording(effectiveRequest)
            await completeRecordingStart(
                activeRecording,
                request: effectiveRequest,
                latencySpan: latencySpan
            )
        } catch is CancellationError {
            await handleRecordingStartFailure(latencySpan: latencySpan, cancellation: true)
        } catch {
            await handleRecordingStartFailure(error, latencySpan: latencySpan, cancellation: false)
        }
    }

    func beginRecording(_ request: RecordingRequest) async throws -> ActiveRecording {
        if request.captureKeystrokes {
            await keystrokeLivePreviewPanelController.prepareForCapture(
                isEnabled: settings.keystrokeLivePreviewEnabled
            )
        }
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
        return try await withTaskCancellationHandler {
            try await startTask.value
        } onCancel: {
            startTask.cancel()
        }
    }

    func completeRecordingStart(
        _ activeRecording: ActiveRecording,
        request: RecordingRequest,
        latencySpan: RecordingStartLatencySpan?
    ) async {
        recordingStartTask = nil
        rememberLastCapture(from: request, capturedAt: activeRecording.date)
        recordingState = .recording(
            activeRecording,
            RecordingMenuClock(startedAt: activeRecording.date)
        )
        await presentCameraPreviewForRecording(request)
        if request.captureKeystrokes {
            keystrokeRecordingSession.start()
        }
        if let latencySpan {
            LuxelRecordingLatencyTelemetry.finishStarted(latencySpan, target: request.target)
        }
    }

    func handleRecordingStartFailure(
        _ error: (any Error)? = nil,
        latencySpan: RecordingStartLatencySpan?,
        cancellation: Bool
    ) async {
        recordingStartTask = nil
        keystrokeRecordingSession.cancel()
        await keystrokeLivePreviewPanelController.close()
        await recordingFramePanelController.close()
        if cancellation {
            recordingState = .idle
        } else if let error {
            recordingState = .failed(errorMessage(error))
        }
        syncCameraPreviewHoverControls()
        if let latencySpan {
            LuxelRecordingLatencyTelemetry.finishFailed(
                latencySpan,
                reason: cancellation ? "start-canceled" : "recorder-start-failed"
            )
        }
    }

    var canBeginRecordingStart: Bool {
        switch recordingState {
        case .idle, .failed:
            true
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    func stopRecording() async -> RecordingStopAction? {
        let stateDescription = recordingState.loggingDescription
        luxelRecordingLogger.info(
            "Stop requested \(stateDescription, privacy: .public) active=\(self.hasActiveRecording, privacy: .public)"
        )

        if cancelRecordingCountdownIfNeeded() {
            return nil
        }

        let context = prepareRecordingStop()
        do {
            return try await finishRecordingStop(context)
        } catch {
            await handleRecordingStopFailure(error, context: context)
            return nil
        }
    }

    func cancelRecordingCountdownIfNeeded() -> Bool {
        guard case .countingDown = recordingState else { return false }
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        recordingState = .starting
        recordingStartTask?.cancel()
        luxelRecordingLogger.info("Stop recording cancelled countdown")
        return true
    }

    func prepareRecordingStop() -> RecordingStopContext {
        let previousState = recordingState
        let activeRecording = previousState.activeRecording
        let captureKind = activeRecording?.options.captureKind ?? .standard
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        recordingState = .stopping
        setCameraPreviewHoverControlsEnabled(false)
        luxelRecordingLogger.info(
            """
      Stop recording transitioned to stopping previous_state=\(previousState.loggingDescription, privacy: .public) \
      active_recording=\(activeRecording?.name ?? "none", privacy: .private) \
      capture_kind=\(captureKind.loggingDescription, privacy: .public)
      """
        )
        return RecordingStopContext(
            previousState: previousState,
            activeRecording: activeRecording,
            captureKind: captureKind
        )
    }

    func finishRecordingStop(
        _ context: RecordingStopContext
    ) async throws -> RecordingStopAction? {
        if context.activeRecording?.options.isAudioOnly == true {
            return try await finishAudioRecordingStop()
        }
        let recording = try await finishScreenRecordingStop(captureKind: context.captureKind)
        return await recordingStopAction(recording: recording, captureKind: context.captureKind)
    }

    func finishAudioRecordingStop() async throws -> RecordingStopAction {
        let recording = try await audioRecordingLifecycleService.stopRecording()
        await finishKeystrokeCapture(for: recording)
        refreshRecentRecordings()
        recordingState = .idle
        syncCameraPreviewHoverControls()
        luxelRecordingLogger.info(
            "Audio recording stop completed output=\(recording.fileURL.lastPathComponent, privacy: .private)"
        )
        return .openEditor(recording.fileURL)
    }

    func finishScreenRecordingStop(
        captureKind: QuickCaptureKind
    ) async throws -> PastRecording {
        luxelRecordingLogger.info("Stop recording closing camera preview")
        await closeCameraPreviewForRecordingStop()
        let recording = try await recordingLifecycleService.stopRecording()
        await finishKeystrokeCapture(for: recording)
        await recordingFramePanelController.close()
        closeCameraPreviewForFinishedRecording()
        refreshRecentRecordings()
        luxelRecordingLogger.info(
            """
      Screen recording stop completed output=\(recording.fileURL.lastPathComponent, privacy: .private) \
      capture_kind=\(captureKind.loggingDescription, privacy: .public)
      """
        )
        return recording
    }

    func finishKeystrokeCapture(for recording: PastRecording) async {
        guard recording.options.captureKeystrokes else {
            return
        }
        do {
            _ = try await keystrokeRecordingSession.stopAndSave(nextTo: recording.primaryMediaURL)
        } catch {
            recordingNoticeMessage = "The recording was saved, but its keystroke data could not be saved."
        }
        await keystrokeLivePreviewPanelController.close()
    }

    func recordingStopAction(
        recording: PastRecording,
        captureKind: QuickCaptureKind
    ) async -> RecordingStopAction? {
        switch captureKind {
        case .standard:
            recordingState = .idle
            syncCameraPreviewHoverControls()
            return .openEditor(recording.primaryMediaURL)
        case .quick(let presetID):
            let action = await runQuickExport(recording: recording, presetID: presetID)
            syncCameraPreviewHoverControls()
            return action
        }
    }

    func handleRecordingStopFailure(
        _ error: any Error,
        context: RecordingStopContext
    ) async {
        let message = errorMessage(error)
        let nsError = error as NSError
        recordingActionErrorMessage = message
        if error.isTerminalRecordingStopFailure {
            keystrokeRecordingSession.cancel()
            await keystrokeLivePreviewPanelController.close()
            closeCameraPreviewForFinishedRecording()
            recordingState = .idle
            refreshRecentRecordings()
        } else {
            recordingState = context.previousState
        }
        syncCameraPreviewHoverControls()
        luxelRecordingLogger.error(
            """
      Stop recording failed previous_state=\(context.previousState.loggingDescription, privacy: .public) \
      restored_state=\(self.recordingState.loggingDescription, privacy: .public) \
      error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code, privacy: .public) \
      message=\(message, privacy: .public)
      """
        )
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

    func toggleKeystrokeCapturePause() {
        guard recordingState.activeRecording?.options.captureKeystrokes == true else {
            return
        }
        keystrokeRecordingSession.toggleUserPause()
        recordingNoticeMessage = keystrokeRecordingSession.isUserPaused
            ? "Keystroke capture paused."
            : "Keystroke capture resumed."
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

    func handleAutoStoppedRecording(
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
        if recording.options.captureKeystrokes {
            await finishKeystrokeCapture(for: recording)
        }
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

    func pauseRecording() async {
        guard case .recording(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .pausing(activeRecording, clock)

        do {
            try await recordingLifecycleService.pauseRecording()
            keystrokeRecordingSession.recordingDidPause()
            recordingState = .paused(activeRecording, clock.paused(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .recording(activeRecording, clock)
        }
    }

    func resumeRecording() async {
        guard case .paused(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .resuming(activeRecording, clock)

        do {
            try await recordingLifecycleService.resumeRecording()
            keystrokeRecordingSession.recordingDidResume()
            recordingState = .recording(activeRecording, clock.resumed(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .paused(activeRecording, clock)
        }
    }
}
