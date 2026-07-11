import Foundation
import LuxelCore
import OSLog

let luxelRecordingLogger = Logger(
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
        frameRate: AutomationRecordingFrameRate? = nil,
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
            let frameRateRequest = requestByApplyingAutomationFrameRate(frameRate, to: request)
            let scheduledRequest = try requestByApplyingAutomationCountdown(
                countdownSeconds,
                to: frameRateRequest
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

    func startAutomationRecording(
        target: CaptureTarget,
        pixelSize: PixelSize,
        presetID: UUID?,
        frameRate: AutomationRecordingFrameRate? = nil,
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
            frameRate: frameRate,
            countdownSeconds: countdownSeconds,
            outputDirectory: outputDirectory,
            latencySpan: latencySpan
        )
    }

    func startAutomationRecordingFromLastCapture(
        presetID: UUID?,
        frameRate: AutomationRecordingFrameRate? = nil,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil
    ) async {
        let captureKind = presetID.map(QuickCaptureKind.quick) ?? .standard
        await startRecordingFromLastCapture(
            captureKind: captureKind,
            entryPoint: .urlAutomation,
            frameRate: frameRate,
            countdownSeconds: countdownSeconds,
            outputDirectory: outputDirectory
        )
    }

    func startAudioOnlyRecording(notchRecordingActionID: NotchActivityActionID? = nil) async {
        if settings.keystrokeOverlayEnabled, inputMonitoringStatus != .authorized {
            presentPermissionPrompt(for: .inputMonitoring)
            return
        }
        guard canBeginRecordingStart else {
            return
        }

        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil

        guard captureCapabilities.audioOnlyRecordingAvailable else {
            recordingState = .failed("No audio source available")
            return
        }

        activeNotchRecordingActionID = notchRecordingActionID
        recordingState = .starting

        do {
            let preparedRequest = try makeAudioRecordingRequest()
            recordingNoticeMessage = preparedRequest.noticeMessage
            if preparedRequest.request.captureKeystrokes {
                await keystrokeLivePreviewPanelController.prepareForCapture(
                    isEnabled: settings.keystrokeLivePreviewEnabled
                )
            }

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
            if preparedRequest.request.captureKeystrokes {
                keystrokeRecordingSession.start()
            }
        } catch {
            keystrokeRecordingSession.cancel()
            await keystrokeLivePreviewPanelController.close()
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
        frameRate: AutomationRecordingFrameRate? = nil,
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
            let request = requestByApplyingAutomationFrameRate(
                frameRate,
                to: preparedRequest.request
            )
            await startRecording(
                request,
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

    private func requestByApplyingAutomationFrameRate(
        _ frameRate: AutomationRecordingFrameRate?,
        to request: RecordingRequest
    ) -> RecordingRequest {
        guard let frameRate else {
            return request
        }

        switch frameRate {
        case .fixed(let fixedFrameRate):
            return request.replacingFrameRate(
                fixedFrameRate,
                matchesDisplayFrameRate: false
            )
        case .matchDisplay:
            return request.replacingFrameRate(
                .fps120,
                matchesDisplayFrameRate: true
            )
        }
    }

}

extension Error {
    var isTerminalRecordingStopFailure: Bool {
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
    var loggingDescription: String {
        switch self {
        case .standard:
            "standard"
        case .quick:
            "quick"
        }
    }
}

struct RecordingStopContext {
    let previousState: RecordingMenuState
    let activeRecording: ActiveRecording?
    let captureKind: QuickCaptureKind
}
