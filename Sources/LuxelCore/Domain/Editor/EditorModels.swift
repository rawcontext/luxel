import Foundation

public struct SourceMedia: Codable, Equatable, Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let pixelSize: PixelSize
    public let nominalFrameRate: FrameRate
    public let hasAudio: Bool

    public init(
        fileURL: URL,
        duration: TimeInterval,
        pixelSize: PixelSize,
        nominalFrameRate: FrameRate,
        hasAudio: Bool
    ) throws {
        guard duration > 0 else {
            throw EditorModelError.invalidDuration
        }

        self.fileURL = fileURL
        self.duration = duration
        self.pixelSize = pixelSize
        self.nominalFrameRate = nominalFrameRate
        self.hasAudio = hasAudio
    }
}

public struct EditorExportDraft: Codable, Equatable, Sendable {
    public let source: SourceMedia
    public let format: ExportFormat
    public let trimRange: TimeRange?
    public let pixelSize: PixelSize?
    public let frameRate: FrameRate?
    public let shouldMute: Bool
    public let shouldCrop: Bool
    public let quality: ExportQuality

    public init(
        source: SourceMedia,
        format: ExportFormat = .mp4,
        trimRange: TimeRange? = nil,
        pixelSize: PixelSize? = nil,
        frameRate: FrameRate? = nil,
        shouldMute: Bool = false,
        shouldCrop: Bool = false,
        quality: ExportQuality = .balanced
    ) {
        self.source = source
        self.format = format
        self.trimRange = trimRange
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.shouldMute = shouldMute
        self.shouldCrop = shouldCrop
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case format
        case trimRange
        case pixelSize
        case frameRate
        case shouldMute
        case shouldCrop
        case quality
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        source = try container.decode(SourceMedia.self, forKey: .source)
        format = try container.decode(ExportFormat.self, forKey: .format)
        trimRange = try container.decodeIfPresent(TimeRange.self, forKey: .trimRange)
        pixelSize = try container.decodeIfPresent(PixelSize.self, forKey: .pixelSize)
        frameRate = try container.decodeIfPresent(FrameRate.self, forKey: .frameRate)
        shouldMute = try container.decode(Bool.self, forKey: .shouldMute)
        shouldCrop = try container.decode(Bool.self, forKey: .shouldCrop)
        quality = try container.decodeIfPresent(ExportQuality.self, forKey: .quality)
            ?? .balanced
    }

    public var exportRequest: ExportRequest {
        get throws {
            try ExportRequest(
                inputFileURL: source.fileURL,
                format: format,
                pixelSize: pixelSize ?? source.pixelSize,
                frameRate: frameRate ?? source.nominalFrameRate,
                timeRange: trimRange ?? TimeRange(start: 0, end: source.duration),
                shouldMute: shouldMute || !source.hasAudio,
                shouldCrop: shouldCrop,
                quality: quality
            )
        }
    }
}

public struct EditorPlaybackLoop: Equatable, Sendable {
    public let trimRange: TimeRange

    public init(trimRange: TimeRange) {
        self.trimRange = trimRange
    }

    public func seekTarget(for currentTime: TimeInterval) -> TimeInterval? {
        guard currentTime >= trimRange.start, currentTime < trimRange.end else {
            return trimRange.start
        }

        return nil
    }
}

public enum EditorSizePreset: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case original
    case percent75
    case percent50
    case percent33
    case percent25
    case percent20
    case percent10

    public var label: String {
        switch self {
        case .original:
            "Original"
        case .percent75:
            "75%"
        case .percent50:
            "50%"
        case .percent33:
            "33%"
        case .percent25:
            "25%"
        case .percent20:
            "20%"
        case .percent10:
            "10%"
        }
    }

    public var scale: Double {
        switch self {
        case .original:
            1
        case .percent75:
            0.75
        case .percent50:
            0.5
        case .percent33:
            0.33
        case .percent25:
            0.25
        case .percent20:
            0.2
        case .percent10:
            0.1
        }
    }

    public func pixelSize(for sourcePixelSize: PixelSize) throws -> PixelSize {
        try PixelSize(
            width: max(1, Int((Double(sourcePixelSize.width) * scale).rounded())),
            height: max(1, Int((Double(sourcePixelSize.height) * scale).rounded()))
        )
    }
}

public enum EditorModelError: Error, Equatable {
    case invalidDuration
}
