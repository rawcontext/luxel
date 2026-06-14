import Foundation

public struct LastCaptureRecordingPlanner: Sendable {
    public init() {}

    public func recordingRequest(
        from memory: LastCaptureMemory?,
        availableTargets: [CaptureTargetOption],
        fallbackWindow: CaptureTargetOption? = nil,
        fallbackDisplay: CaptureTargetOption? = nil,
        outputFileURL: URL,
        captureKind: QuickCaptureKind = .standard
    ) throws -> RecordingRequest {
        guard let memory else {
            throw LastCaptureRecordingPlannerError.missingLastCapture
        }

        guard let resolution = memory.resolvedTarget(
            availableTargets: availableTargets,
            fallbackWindow: fallbackWindow,
            fallbackDisplay: fallbackDisplay
        ) else {
            throw LastCaptureRecordingPlannerError.targetUnavailable
        }

        return RecordingRequest(
            target: resolution.target,
            outputFileURL: outputFileURL,
            pixelSize: resolution.pixelSize,
            frameRate: try FrameRate(resolution.options.frameRate),
            showCursor: resolution.options.showCursor,
            highlightClicks: resolution.options.highlightClicks,
            captureKeystrokes: resolution.options.captureKeystrokes,
            camera: resolution.options.camera,
            audio: resolution.options.audio,
            videoCodec: resolution.options.videoCodec,
            captureKind: captureKind
        )
    }
}

public enum LastCaptureRecordingPlannerError: LocalizedError, Equatable, Sendable {
    case missingLastCapture
    case targetUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingLastCapture:
            "No previous capture is available"
        case .targetUnavailable:
            "The previous capture target is no longer available"
        }
    }
}
