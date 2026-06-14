import Foundation

public enum ScreenshotFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case png
    case jpeg
    case heic

    public var supportsAlpha: Bool {
        switch self {
        case .png, .heic:
            true
        case .jpeg:
            false
        }
    }
}

public enum ScreenshotScale: String, Codable, Equatable, Sendable {
    case native
    case points
}

public enum CaptureBackdrop: String, Codable, Equatable, Sendable {
    case opaque
    case transparent
}

public struct ScreenshotRequest: Codable, Equatable, Sendable {
    public let target: CaptureTarget
    public let includeCursor: Bool
    public let scale: ScreenshotScale
    public let format: ScreenshotFormat
    public let backdrop: CaptureBackdrop

    public init(
        target: CaptureTarget,
        includeCursor: Bool,
        scale: ScreenshotScale = .native,
        format: ScreenshotFormat = .png,
        backdrop: CaptureBackdrop = .opaque
    ) throws {
        if backdrop == .transparent {
            guard target.isWindow else {
                throw ScreenshotModelError.transparentBackdropRequiresWindowTarget
            }

            guard format.supportsAlpha else {
                throw ScreenshotModelError.transparentBackdropRequiresAlphaCapableFormat
            }
        }

        self.target = target
        self.includeCursor = includeCursor
        self.scale = scale
        self.format = format
        self.backdrop = backdrop
    }
}

public struct ImageData: Equatable, Sendable {
    public let data: Data
    public let format: ScreenshotFormat
    public let pixelSize: PixelSize

    public init(data: Data, format: ScreenshotFormat, pixelSize: PixelSize) throws {
        guard !data.isEmpty else {
            throw ScreenshotModelError.emptyImageData
        }

        self.data = data
        self.format = format
        self.pixelSize = pixelSize
    }
}

public enum ScreenshotModelError: Error, Equatable {
    case transparentBackdropRequiresWindowTarget
    case transparentBackdropRequiresAlphaCapableFormat
    case emptyImageData
}

private extension CaptureTarget {
    var isWindow: Bool {
        if case .window = self {
            return true
        }

        return false
    }
}
