import Foundation

public struct ScreenshotCapturePlanner: Sendable {
    public init() {}

    public func captureJob(
        target: CaptureTarget,
        includeCursor: Bool,
        format: ScreenshotFormat,
        destinations: [ScreenshotDestination],
        outputDirectory: URL,
        now: Date,
        calendar: Calendar = .current,
        scale: ScreenshotScale = .native,
        backdrop: CaptureBackdrop = .opaque
    ) throws -> ScreenshotCaptureJob {
        let request = try ScreenshotRequest(
            target: target,
            includeCursor: includeCursor,
            scale: scale,
            format: format,
            backdrop: target.isWindow ? backdrop : .opaque
        )
        let outputName = RecordingName.timestamped(now: now, calendar: calendar).value
        let outputFileURL = destinations.contains(where: \.requiresFileURL)
            ? outputDirectory
            .appending(path: outputName)
            .appendingPathExtension(format.fileExtension)
            : nil

        return try ScreenshotCaptureJob(
            request: request,
            destinations: destinations,
            outputFileURL: outputFileURL,
            historyName: outputName
        )
    }
}

private extension CaptureTarget {
    var isWindow: Bool {
        if case .window = self {
            return true
        }

        return false
    }
}
