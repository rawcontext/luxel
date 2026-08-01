import Foundation
import LuxelCore
import Testing

func makeTestWindowOption(
    id: UInt32,
    frame: CaptureRect? = nil
) throws -> CaptureTargetOption {
    let resolvedFrame = try frame ?? CaptureRect(x: 0, y: 0, width: 800, height: 600)
    return try CaptureTargetOption(
        id: "window-\(id)",
        kind: .window,
        title: "Window \(id)",
        target: .window(id: id),
        pixelSize: PixelSize(width: resolvedFrame.width, height: resolvedFrame.height),
        frame: resolvedFrame
    )
}

func makeTestDisplayOption(id: UInt32) throws -> CaptureTargetOption {
    try CaptureTargetOption(
        id: "display-\(id)",
        kind: .display,
        title: "Display \(id)",
        target: .display(DisplayID(id)),
        pixelSize: PixelSize(width: 1920, height: 1080),
        frame: CaptureRect(x: 0, y: 0, width: 1920, height: 1080)
    )
}

func expectQuickCaptureKind(
    _ request: RecordingRequest,
    presetID: UUID
) {
    #expect(request.captureKind == .quick(presetID: presetID))
    #expect(request.recordingOptions.captureKind == .quick(presetID: presetID))
}
