import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func captureScreenshotFromSelectedTarget() async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil

        guard let selectedCaptureTarget else {
            recordingActionErrorMessage = "No capture target selected"
            return
        }

        await captureScreenshot(target: selectedCaptureTarget.target)
    }

    func captureScreenshot(from draft: CaptureSelectionDraft) async {
        do {
            let target = try draft.captureTarget
            await captureScreenshot(target: target)
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func captureFullscreenScreenshot() async {
        guard let displayTarget = fullscreenCaptureTarget else {
            recordingActionErrorMessage = "No display target available"
            return
        }

        await captureScreenshot(target: displayTarget.target)
    }

    func captureActiveWindowScreenshot() async {
        guard canSelectArea else {
            recordingActionErrorMessage = "No active window target available"
            return
        }

        await refreshCaptureTargets()

        guard let windowTarget = activeWindowCaptureTargetResolver.resolve(
            from: captureTargets,
            orderedWindowIDs: activeWindowCatalog.orderedActiveWindowIDs()
        ) else {
            recordingActionErrorMessage = "No active window target available"
            return
        }

        await captureScreenshot(target: windowTarget.target)
    }

    private func captureScreenshot(target: CaptureTarget) async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil

        do {
            _ = try await performScreenshotCapture(target: target, format: settings.screenshotFormat)
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func captureAutomationScreenshot(
        target: CaptureTarget,
        format: ScreenshotFormat?
    ) async throws -> AutomationExecutionResult {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil

        let capture = try await performScreenshotCapture(
            target: target,
            format: format ?? settings.screenshotFormat
        )

        if let fileURL = capture.result.fileURL {
            return .file(fileURL)
        }

        return .accepted
    }

    private func performScreenshotCapture(
        target: CaptureTarget,
        format: ScreenshotFormat
    ) async throws -> (job: ScreenshotCaptureJob, result: ScreenshotCaptureResult) {
        let job = try screenshotCapturePlanner.captureJob(
            target: target,
            includeCursor: settings.cursorMode == .baked,
            format: format,
            destinations: settings.screenshotDestinations,
            outputDirectory: settings.recordingsDirectory,
            now: Date(),
            backdrop: settings.screenshotBackdrop
        )
        let result = try await screenshotCaptureService.capture(job)
        refreshRecentRecordings()
        presentScreenshotThumbnailIfNeeded(result, job: job)
        return (job, result)
    }

    private func presentScreenshotThumbnailIfNeeded(
        _ result: ScreenshotCaptureResult,
        job: ScreenshotCaptureJob
    ) {
        guard settings.screenshotShowThumbnail else {
            return
        }

        let fileName = result.fileURL?.lastPathComponent
            ?? job.outputFileURL?.lastPathComponent
            ?? "\(job.historyName ?? "Luxel Screenshot").\(job.request.format.fileExtension)"
        screenshotThumbnailPresenter.present(ScreenshotThumbnailItem(
            imageData: result.imageData,
            fileName: fileName,
            fileURL: result.fileURL
        ))
    }
}
