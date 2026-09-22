import Foundation

public struct RecordingStopFailure: Error, Sendable {
    public enum Stage: String, Sendable {
        case stoppingCapture
        case finishingWriter
        case composingSegments
    }

    public let stage: Stage
    public let underlyingError: any Error

    public init(stage: Stage, underlyingError: any Error) {
        self.stage = stage
        self.underlyingError = underlyingError
    }

    public var isTerminal: Bool {
        stage != .stoppingCapture
    }

    public var diagnosticDescription: String {
        let error = underlyingError as NSError
        var description = "stage=\(stage.rawValue) error_domain=\(error.domain) error_code=\(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            description += " underlying_domain=\(underlying.domain) underlying_code=\(underlying.code)"
        }
        return description
    }
}

extension RecordingStopFailure: LocalizedError {
    public var errorDescription: String? {
        if isTerminal {
            LuxelLocalization.string("Recording stopped, but the video could not be saved.")
        } else {
            LuxelLocalization.string("The recording could not be stopped. Try stopping again.")
        }
    }
}
