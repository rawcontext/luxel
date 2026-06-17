import CoreGraphics
import LuxelCore

@MainActor
protocol CropperLoupeImageProvider: AnyObject {
    func image(for sample: CaptureLoupeSample, display: DisplayBounds) async throws -> CGImage
}

@MainActor
final class ScreenCaptureKitCropperLoupeImageProvider: CropperLoupeImageProvider {
    private let capturer: ScreenCaptureKitStillCapturer

    init(exclusionRegistry: CaptureExclusionRegistry) {
        capturer = ScreenCaptureKitStillCapturer(
            contentFilterProvider: ShareableContentFilterProvider(exclusionRegistry: exclusionRegistry)
        )
    }

    func image(for sample: CaptureLoupeSample, display: DisplayBounds) async throws -> CGImage {
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: sample.sourceRect,
            minimumWidth: 1,
            minimumHeight: 1
        )
        let request = try ScreenshotRequest(
            target: draft.captureTarget,
            includeCursor: false,
            scale: .native,
            format: .png
        )

        return try await capturer.captureImage(request)
    }
}
