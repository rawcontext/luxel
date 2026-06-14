import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func captureScreenshotFromSelectedTarget() async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil

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
        quickExportStatusMessage = nil

        do {
            let capture = try await performScreenshotCapture(target: target, format: settings.screenshotFormat)
            quickExportStatusMessage = screenshotStatusText(for: capture.result)
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
        quickExportStatusMessage = nil

        let capture = try await performScreenshotCapture(
            target: target,
            format: format ?? settings.screenshotFormat
        )
        quickExportStatusMessage = screenshotStatusText(for: capture.result)

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
            includeCursor: settings.showCursor,
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

    private func screenshotStatusText(for result: ScreenshotCaptureResult) -> String {
        if let fileURL = result.fileURL {
            return "Captured \(fileURL.lastPathComponent)"
        }

        if result.completedDestinations.contains(.clipboard) {
            return "Copied screenshot"
        }

        return "Screenshot capture failed"
    }
}
