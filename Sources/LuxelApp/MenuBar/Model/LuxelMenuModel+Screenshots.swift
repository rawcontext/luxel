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

    private func captureScreenshot(target: CaptureTarget) async {
        recordingNoticeMessage = nil
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil

        do {
            let job = try screenshotCapturePlanner.captureJob(
                target: target,
                includeCursor: settings.showCursor,
                format: settings.screenshotFormat,
                destinations: settings.screenshotDestinations,
                outputDirectory: settings.recordingsDirectory,
                now: Date()
            )
            let result = try await screenshotCaptureService.capture(job)
            refreshRecentRecordings()
            quickExportStatusMessage = screenshotStatusText(for: result)
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
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
