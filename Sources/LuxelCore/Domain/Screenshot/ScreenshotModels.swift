import Foundation

public enum ScreenshotFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case png
    case jpeg
    case heic

    public var fileExtension: String {
        rawValue
    }

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

public enum ScreenshotDestination: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case clipboard
    case file
    case preview

    public var requiresFileURL: Bool {
        switch self {
        case .file, .preview:
            true
        case .clipboard:
            false
        }
    }
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

public struct FrameGrabRequest: Codable, Equatable, Sendable {
    public let sourceFileURL: URL
    public let time: TimeInterval
    public let cropRect: CaptureRect?
    public let format: ScreenshotFormat

    public init(
        sourceFileURL: URL,
        time: TimeInterval,
        cropRect: CaptureRect? = nil,
        format: ScreenshotFormat = .png
    ) throws {
        guard time.isFinite, time >= 0 else {
            throw ScreenshotModelError.invalidFrameTime
        }

        self.sourceFileURL = sourceFileURL
        self.time = time
        self.cropRect = cropRect
        self.format = format
    }

    public var suggestedFileName: String {
        let sourceName = sourceFileURL.deletingPathExtension().lastPathComponent
        return "\(sourceName) (frame \(Self.frameTimeText(time))).\(format.fileExtension)"
    }

    private static func frameTimeText(_ time: TimeInterval) -> String {
        let totalTenths = Int((time * 10).rounded(.down))
        let minutes = totalTenths / 600
        let seconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10

        return String(format: "%d.%02d.%d", minutes, seconds, tenths)
    }
}

public enum ScreenshotModelError: Error, Equatable {
    case transparentBackdropRequiresWindowTarget
    case transparentBackdropRequiresAlphaCapableFormat
    case emptyImageData
    case emptyScreenshotDestinations
    case fileDestinationRequiresOutputURL
    case invalidFrameTime
}

private extension CaptureTarget {
    var isWindow: Bool {
        if case .window = self {
            return true
        }

        return false
    }
}
