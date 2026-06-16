import Foundation

public enum QuickCaptureKind: Codable, Equatable, Sendable {
    case standard
    case quick(presetID: UUID)
}

public struct LastCaptureMemory: Codable, Equatable, Sendable {
    public let target: CaptureTarget
    public let pixelSize: PixelSize
    public let options: RecordingOptions
    public let capturedAt: Date

    public init(
        target: CaptureTarget,
        pixelSize: PixelSize,
        options: RecordingOptions,
        capturedAt: Date
    ) {
        self.target = target
        self.pixelSize = pixelSize
        self.options = options
        self.capturedAt = capturedAt
    }

    public init(request: RecordingRequest, capturedAt: Date) {
        self.init(
            target: request.target,
            pixelSize: request.pixelSize,
            options: request.recordingOptions,
            capturedAt: capturedAt
        )
    }

    public func restoredTopLeftSelection(
        in display: DisplayBounds,
        availableTargets: [CaptureTargetOption] = []
    ) -> CaptureRect? {
        switch target {
        case .area(let displayID, let rect) where displayID == display.id:
            return try? CaptureCoordinateMapper.topLeftSelection(fromRecordingRect: rect, in: display)
        case .display, .window, .area:
            return nil
        }
    }

    public func resolvedTarget(
        availableTargets: [CaptureTargetOption],
        fallbackWindow: CaptureTargetOption? = nil,
        fallbackDisplay: CaptureTargetOption? = nil
    ) -> LastCaptureTargetResolution? {
        switch target {
        case .window:
            if let exactMatch = availableTargets.first(where: { $0.target == target }) {
                return LastCaptureTargetResolution(option: exactMatch, options: options)
            }

            if let fallbackWindow {
                return LastCaptureTargetResolution(option: fallbackWindow, options: options)
            }

            return fallbackDisplay.map { LastCaptureTargetResolution(option: $0, options: options) }
        case .display:
            if let exactMatch = availableTargets.first(where: { $0.target == target }) {
                return LastCaptureTargetResolution(option: exactMatch, options: options)
            }

            return fallbackDisplay.map { LastCaptureTargetResolution(option: $0, options: options) }
        case .area(let displayID, _):
            if availableTargets.contains(where: { $0.target == .display(displayID) }) {
                return LastCaptureTargetResolution(
                    target: target,
                    pixelSize: pixelSize,
                    options: options
                )
            }

            return fallbackDisplay.map { LastCaptureTargetResolution(option: $0, options: options) }
        }
    }
}

public struct LastCaptureTargetResolution: Equatable, Sendable {
    public let target: CaptureTarget
    public let pixelSize: PixelSize
    public let options: RecordingOptions

    public init(target: CaptureTarget, pixelSize: PixelSize, options: RecordingOptions) {
        self.target = target
        self.pixelSize = pixelSize
        self.options = options
    }

    public init(option: CaptureTargetOption, options: RecordingOptions) {
        self.init(
            target: option.target,
            pixelSize: option.pixelSize,
            options: options
        )
    }
}
