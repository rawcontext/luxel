import Foundation

public enum ExportFormat: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case gif
    case hevc
    case mp4
    case webm
    case apng
    case av1
    case proRes422 = "prores422"
    case proRes4444 = "prores4444"
    case m4a
    case alac
    case wav
    case caf
    case flac

    public static let appleNativeV1Formats: [ExportFormat] = [
        .hevc, .mp4, .proRes422, .proRes4444, .gif, .apng
    ]
    public static let externalNativeCodecFormats: [ExportFormat] = [.webm, .av1]
    public static let videoExportMenuFormats: [ExportFormat] = [
        .av1, .webm, .hevc, .mp4, .proRes422, .proRes4444, .gif, .apng
    ]
    public static let audioOnlyFormats: [ExportFormat] = [.m4a, .alac, .wav, .caf, .flac]

    public var isAppleNativeV1Format: Bool {
        Self.appleNativeV1Formats.contains(self)
    }

    public var isAudioOnlyFormat: Bool {
        Self.audioOnlyFormats.contains(self)
    }

    public var requiresExternalNativeCodec: Bool {
        switch self {
        case .webm, .av1:
            true
        case .gif, .hevc, .mp4, .proRes422, .proRes4444, .apng, .m4a, .alac, .wav, .caf, .flac:
            false
        }
    }

    public var fileExtension: String {
        switch self {
        case .av1, .hevc, .mp4:
            "mp4"
        case .proRes422, .proRes4444:
            "mov"
        case .gif:
            "gif"
        case .webm:
            "webm"
        case .apng:
            "apng"
        case .m4a, .alac:
            "m4a"
        case .wav:
            "wav"
        case .caf:
            "caf"
        case .flac:
            "flac"
        }
    }

    public var prettyName: String {
        switch self {
        case .gif:
            "GIF"
        case .hevc:
            "MP4 (HEVC)"
        case .mp4:
            "MP4 (H.264)"
        case .av1:
            "MP4 (AV1)"
        case .proRes422:
            "MOV (ProRes 422)"
        case .proRes4444:
            "MOV (ProRes 4444)"
        case .webm:
            "WebM (VP9)"
        case .apng:
            "APNG"
        case .m4a:
            "M4A (AAC)"
        case .alac:
            "M4A (Apple Lossless)"
        case .wav:
            "WAV"
        case .caf:
            "CAF"
        case .flac:
            "FLAC"
        }
    }

    public var dropsAudio: Bool {
        switch self {
        case .gif, .apng:
            true
        case .av1, .hevc, .mp4, .proRes422, .proRes4444, .webm, .m4a, .alac, .wav, .caf, .flac:
            false
        }
    }

    public var requiresEvenPixelDimensions: Bool {
        switch self {
        case .av1, .hevc, .mp4, .proRes422, .proRes4444, .webm:
            true
        case .gif, .apng, .m4a, .alac, .wav, .caf, .flac:
            false
        }
    }
}

public enum ExportQuality: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case compact
    case balanced
    case high
    case lossless

    public var label: String {
        switch self {
        case .compact:
            LuxelLocalization.string("Compact")
        case .balanced:
            LuxelLocalization.string("Balanced")
        case .high:
            LuxelLocalization.string("High")
        case .lossless:
            LuxelLocalization.string("Lossless")
        }
    }

    public static func availableQualities(for format: ExportFormat) -> [ExportQuality] {
        switch format {
        case .mp4, .hevc, .gif, .webm, .av1:
            [.compact, .balanced, .high]
        case .proRes422, .proRes4444:
            [.high]
        case .apng:
            [.lossless]
        case .m4a:
            [.balanced]
        case .alac, .wav, .caf, .flac:
            [.lossless]
        }
    }

    public func isAvailable(for format: ExportFormat) -> Bool {
        Self.availableQualities(for: format).contains(self)
    }

    public static func defaultQuality(for format: ExportFormat) -> ExportQuality {
        switch format {
        case .apng:
            .lossless
        case .m4a:
            .balanced
        case .alac, .wav, .caf, .flac:
            .lossless
        case .proRes422, .proRes4444:
            .high
        case .mp4, .hevc, .gif, .webm, .av1:
            .balanced
        }
    }

    public func videoBitsPerPixel(for format: ExportFormat) -> Double? {
        Self.videoBitsPerPixelByFormat[format]?[self]
    }

    private static let videoBitsPerPixelByFormat: [ExportFormat: [ExportQuality: Double]] = [
        .mp4: [.compact: 0.07, .balanced: 0.12, .high: 0.20],
        .hevc: [.compact: 0.05, .balanced: 0.09, .high: 0.15],
        .proRes422: [.high: 2.35],
        .proRes4444: [.high: 5.30]
    ]
}

public struct ExportMemory: Codable, Equatable, Sendable {
    public var sizePreset: EditorSizePreset
    public var frameRate: FrameRate
    public var quality: ExportQuality
    public var gifOptions: GIFRenderOptions?

    public init(
        sizePreset: EditorSizePreset,
        frameRate: FrameRate,
        quality: ExportQuality,
        gifOptions: GIFRenderOptions? = nil
    ) {
        self.sizePreset = sizePreset
        self.frameRate = frameRate
        self.quality = quality
        self.gifOptions = gifOptions
    }
}

public struct PixelSize: Codable, Equatable, Sendable {
    public static let hd1280x720 = PixelSize(uncheckedWidth: 1280, height: 720)
    public static let fullHD1920x1080 = PixelSize(uncheckedWidth: 1920, height: 1080)
    public static let svga800x600 = PixelSize(uncheckedWidth: 800, height: 600)

    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw ExportModelError.invalidPixelSize
        }

        self.width = width
        self.height = height
    }

    private init(uncheckedWidth width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var roundedToEvenDimensions: PixelSize {
        get throws {
            try PixelSize(width: Self.makeEven(width), height: Self.makeEven(height))
        }
    }

    private static func makeEven(_ value: Int) -> Int {
        2 * Int((Double(value) / 2).rounded())
    }
}

extension PixelSize {
    public func scaled(by scale: Double) throws -> PixelSize {
        try PixelSize(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }
}

public struct FrameRate: Codable, Equatable, Sendable {
    public static let fps30 = FrameRate(uncheckedFramesPerSecond: 30)
    public static let fps60 = FrameRate(uncheckedFramesPerSecond: 60)
    public static let fps120 = FrameRate(uncheckedFramesPerSecond: 120)

    public let framesPerSecond: Int

    public init(_ framesPerSecond: Int) throws {
        guard framesPerSecond > 0 else {
            throw ExportModelError.invalidFrameRate
        }

        self.framesPerSecond = framesPerSecond
    }

    private init(uncheckedFramesPerSecond framesPerSecond: Int) {
        self.framesPerSecond = framesPerSecond
    }
}

public struct PlaybackSpeed: Codable, Equatable, Sendable {
    public static let normal = PlaybackSpeed(uncheckedValue: 1)

    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, (0.1...10).contains(value) else {
            throw ExportModelError.invalidPlaybackSpeed
        }

        self.value = value
    }

    private init(uncheckedValue value: Double) {
        self.value = value
    }

    public static func == (lhs: PlaybackSpeed, rhs: PlaybackSpeed) -> Bool {
        abs(lhs.value - rhs.value) < 0.000_001
    }
}

public struct TimeRange: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) throws {
        guard start >= 0, end > start else {
            throw ExportModelError.invalidTimeRange
        }

        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end - start
    }
}
