import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func startRecording(from draft: CaptureSelectionDraft) async {
        do {
            let target = try draft.captureTarget
            let pixelSize = try draft.pixelSize
            await startRecording(target: target, pixelSize: pixelSize, captureKind: .standard)
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func startRecordingFromSelectedTarget() async {
        guard let selectedCaptureTarget else {
            recordingState = .failed("No capture target selected")
            return
        }

        await startRecording(
            target: selectedCaptureTarget.target,
            pixelSize: selectedCaptureTarget.pixelSize,
            captureKind: .standard
        )
    }

    func startFullscreenRecording(entryPoint: RecordingStartEntryPoint = .recordFullscreenShortcut) async {
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
            latencySpan: latencySpan
        )
    }

    func startActiveWindowRecording(entryPoint: RecordingStartEntryPoint = .recordActiveWindowShortcut) async {
        guard canSelectArea else {
            recordingState = .failed("No active window target available")
            return
        }

        let latencySpan = LuxelRecordingLatencyTelemetry.begin(entryPoint: entryPoint)
        await refreshCaptureTargets()

        guard let windowTarget = activeWindowCaptureTargetResolver.resolve(
            from: captureTargets,
            orderedWindowIDs: activeWindowCatalog.orderedActiveWindowIDs()
        ) else {
            recordingState = .failed("No active window target available")
            LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "no-active-window-target")
            return
        }

        await startRecording(
            target: windowTarget.target,
            pixelSize: windowTarget.pixelSize,
            captureKind: .standard,
            latencySpan: latencySpan
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
        entryPoint: RecordingStartEntryPoint
    ) async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil
        let latencySpan = LuxelRecordingLatencyTelemetry.begin(entryPoint: entryPoint)

        do {
            let request = try lastCaptureRecordingPlanner.recordingRequest(
                from: settings.lastCaptureMemory,
                availableTargets: captureTargets,
                fallbackDisplay: lastCaptureFallbackDisplay,
                outputFileURL: try nextRecordingFileURL(now: Date()),
                captureKind: captureKind
            )
            await startRecording(request, latencySpan: latencySpan)
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

        await startRecording(
            target: selectedCaptureTarget.target,
            pixelSize: selectedCaptureTarget.pixelSize,
            captureKind: .quick(presetID: presetID)
        )
    }

    func startAudioOnlyRecording() async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil

        guard microphoneStatus == .authorized else {
            recordingState = .failed("Microphone permission is required")
            return
        }

        recordingState = .starting

        do {
            let preparedRequest = try makeAudioRecordingRequest()
            recordingNoticeMessage = preparedRequest.noticeMessage

            let recordingName = preparedRequest.request.outputFileURL
                .deletingPathExtension()
                .lastPathComponent
            let activeRecording = try await audioRecordingLifecycleService.startRecording(
                preparedRequest.request,
                name: recordingName
            )
            recordingState = .recording(
                activeRecording,
                RecordingMenuClock(startedAt: activeRecording.date)
            )
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    private func startRecording(
        target: CaptureTarget,
        pixelSize: PixelSize,
        captureKind: QuickCaptureKind,
        latencySpan: RecordingStartLatencySpan? = nil
    ) async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil

        do {
            let preparedRequest = try makeRecordingRequest(
                target: target,
                pixelSize: pixelSize,
                captureKind: captureKind
            )
            await startRecording(
                preparedRequest.request,
                noticeMessage: preparedRequest.noticeMessage,
                latencySpan: latencySpan
            )
        } catch {
            recordingState = .failed(errorMessage(error))
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "request-build-failed")
            }
        }
    }

    private func startRecording(
        _ request: RecordingRequest,
        noticeMessage: String? = nil,
        latencySpan: RecordingStartLatencySpan? = nil
    ) async {
        recordingNoticeMessage = noticeMessage
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil
        recordingState = .starting

        do {
            let recordingName = request.outputFileURL.deletingPathExtension().lastPathComponent
            let activeRecording = try await recordingLifecycleService.startRecording(
                request,
                name: recordingName
            )
            rememberLastCapture(from: request, capturedAt: activeRecording.date)
            recordingState = .recording(
                activeRecording,
                RecordingMenuClock(startedAt: activeRecording.date)
            )
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishStarted(latencySpan, target: request.target)
            }
        } catch {
            recordingState = .failed(errorMessage(error))
            if let latencySpan {
                LuxelRecordingLatencyTelemetry.finishFailed(latencySpan, reason: "recorder-start-failed")
            }
        }
    }

    func stopRecording() async -> RecordingStopAction? {
        let previousRecordingState = recordingState
        let activeRecording = previousRecordingState.activeRecording
        let captureKind = activeRecording?.options.captureKind ?? .standard
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        recordingState = .stopping

        do {
            if activeRecording?.options.isAudioOnly == true {
                let recording = try await audioRecordingLifecycleService.stopRecording()
                refreshRecentRecordings()
                recordingState = .idle
                quickExportStatusMessage = "Recorded \(recording.fileURL.lastPathComponent)"
                return .audioRecorded(recording.fileURL)
            }

            let recording = try await recordingLifecycleService.stopRecording()
            refreshRecentRecordings()

            switch captureKind {
            case .standard:
                recordingState = .idle
                return .openEditor(recording.fileURL)
            case .quick(let presetID):
                return await runQuickExport(recording: recording, presetID: presetID)
            }
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = previousRecordingState
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
        case .idle, .starting, .pausing, .resuming, .stopping, .exporting, .failed:
            return
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
        quickExportStatusMessage = nil
        recordingState = .stopping
        refreshRecentRecordings()

        switch recording.options.captureKind {
        case .standard:
            recordingState = .idle
            openRecording(recording.fileURL)
        case .quick(let presetID):
            _ = await runQuickExport(recording: recording, presetID: presetID)
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
