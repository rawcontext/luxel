import Foundation

public struct SourceMedia: Codable, Equatable, Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let hasVideo: Bool
    public let pixelSize: PixelSize
    public let nominalFrameRate: FrameRate
    public let audioTracks: [AudioTrackKind]
    public let hasAlpha: Bool
    public var hasAudio: Bool {
        !audioTracks.isEmpty
    }
    public var isAudioOnly: Bool {
        !hasVideo && hasAudio
    }

    public init(
        fileURL: URL,
        duration: TimeInterval,
        pixelSize: PixelSize,
        nominalFrameRate: FrameRate,
        hasAudio: Bool,
        hasVideo: Bool = true,
        hasAlpha: Bool = false,
        audioTracks: [AudioTrackKind]? = nil
    ) throws {
        guard duration > 0 else {
            throw EditorModelError.invalidDuration
        }

        self.fileURL = fileURL
        self.duration = duration
        self.hasVideo = hasVideo
        self.pixelSize = pixelSize
        self.nominalFrameRate = nominalFrameRate
        self.audioTracks = audioTracks ?? Self.defaultAudioTracks(hasAudio: hasAudio)
        self.hasAlpha = hasAlpha
    }

    public static func audioOnly(
        fileURL: URL,
        duration: TimeInterval,
        audioTracks: [AudioTrackKind] = [.system]
    ) throws -> SourceMedia {
        try SourceMedia(
            fileURL: fileURL,
            duration: duration,
            pixelSize: PixelSize(width: 1, height: 1),
            nominalFrameRate: FrameRate(1),
            hasAudio: !audioTracks.isEmpty,
            hasVideo: false,
            audioTracks: audioTracks
        )
    }

    public func replacingFileURL(_ fileURL: URL) throws -> SourceMedia {
        try SourceMedia(
            fileURL: fileURL,
            duration: duration,
            pixelSize: pixelSize,
            nominalFrameRate: nominalFrameRate,
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            hasAlpha: hasAlpha,
            audioTracks: audioTracks
        )
    }

    private enum CodingKeys: String, CodingKey {
        case fileURL
        case duration
        case hasVideo
        case pixelSize
        case nominalFrameRate
        case hasAudio
        case audioTracks
        case hasAlpha
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let audioTracks = try container.decodeIfPresent([AudioTrackKind].self, forKey: .audioTracks)
        let hasAudio =
            try container.decodeIfPresent(Bool.self, forKey: .hasAudio)
            ?? !(audioTracks?.isEmpty ?? true)

        try self.init(
            fileURL: container.decode(URL.self, forKey: .fileURL),
            duration: container.decode(TimeInterval.self, forKey: .duration),
            pixelSize: container.decode(PixelSize.self, forKey: .pixelSize),
            nominalFrameRate: container.decode(FrameRate.self, forKey: .nominalFrameRate),
            hasAudio: hasAudio,
            hasVideo: container.decodeIfPresent(Bool.self, forKey: .hasVideo) ?? true,
            hasAlpha: container.decodeIfPresent(Bool.self, forKey: .hasAlpha) ?? false,
            audioTracks: audioTracks
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(duration, forKey: .duration)
        try container.encode(hasVideo, forKey: .hasVideo)
        try container.encode(pixelSize, forKey: .pixelSize)
        try container.encode(nominalFrameRate, forKey: .nominalFrameRate)
        try container.encode(hasAudio, forKey: .hasAudio)
        try container.encode(audioTracks, forKey: .audioTracks)
        try container.encode(hasAlpha, forKey: .hasAlpha)
    }

    private static func defaultAudioTracks(hasAudio: Bool) -> [AudioTrackKind] {
        hasAudio ? [.system] : []
    }
}

public struct EditorExportDraft: Codable, Equatable, Sendable {
    public let source: SourceMedia
    public let format: ExportFormat
    public let trimRange: TimeRange?
    public let pixelSize: PixelSize?
    public let frameRate: FrameRate?
    public let shouldMute: Bool
    public let audioMix: AudioMixPlan?
    public let shouldCrop: Bool
    public let cropRect: CaptureRect?
    public let quality: ExportQuality
    public let speed: PlaybackSpeed
    public let gifOptions: GIFRenderOptions?
    public let cursorOptions: CursorRenderOptions?
    public let keystrokeOptions: KeystrokeRenderOptions?
    public let captionOptions: CaptionRenderOptions?
    public let cameraOverlay: CameraOverlayPlan?
    public let zoomBlocks: [ZoomBlock]

    public init(
        source: SourceMedia,
        format: ExportFormat = .mp4,
        trimRange: TimeRange? = nil,
        pixelSize: PixelSize? = nil,
        frameRate: FrameRate? = nil,
        shouldMute: Bool = false,
        audioMix: AudioMixPlan? = nil,
        shouldCrop: Bool = false,
        cropRect: CaptureRect? = nil,
        quality: ExportQuality = .balanced,
        speed: PlaybackSpeed = .normal,
        gifOptions: GIFRenderOptions? = nil,
        cursorOptions: CursorRenderOptions? = nil,
        keystrokeOptions: KeystrokeRenderOptions? = nil,
        captionOptions: CaptionRenderOptions? = nil,
        cameraOverlay: CameraOverlayPlan? = nil,
        zoomBlocks: [ZoomBlock] = []
    ) {
        self.source = source
        self.format = format
        self.trimRange = trimRange
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.shouldMute = shouldMute
        self.audioMix = audioMix
        self.shouldCrop = shouldCrop
        self.cropRect = cropRect
        self.quality = quality
        self.speed = speed
        self.gifOptions = gifOptions
        self.cursorOptions = cursorOptions
        self.keystrokeOptions = keystrokeOptions
        self.captionOptions = captionOptions
        self.cameraOverlay = cameraOverlay
        self.zoomBlocks = zoomBlocks
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case format
        case trimRange
        case pixelSize
        case frameRate
        case shouldMute
        case audioMix
        case shouldCrop
        case cropRect
        case quality
        case speed
        case gifOptions
        case cursorOptions
        case keystrokeOptions
        case captionOptions
        case cameraOverlay
        case zoomBlocks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        source = try container.decode(SourceMedia.self, forKey: .source)
        format = try container.decode(ExportFormat.self, forKey: .format)
        trimRange = try container.decodeIfPresent(TimeRange.self, forKey: .trimRange)
        pixelSize = try container.decodeIfPresent(PixelSize.self, forKey: .pixelSize)
        frameRate = try container.decodeIfPresent(FrameRate.self, forKey: .frameRate)
        shouldMute = try container.decode(Bool.self, forKey: .shouldMute)
        audioMix = try container.decodeIfPresent(AudioMixPlan.self, forKey: .audioMix)
        shouldCrop = try container.decode(Bool.self, forKey: .shouldCrop)
        cropRect = try container.decodeIfPresent(CaptureRect.self, forKey: .cropRect)
        quality =
            try container.decodeIfPresent(ExportQuality.self, forKey: .quality)
            ?? .balanced
        speed =
            try container.decodeIfPresent(PlaybackSpeed.self, forKey: .speed)
            ?? .normal
        gifOptions = try container.decodeIfPresent(GIFRenderOptions.self, forKey: .gifOptions)
        cursorOptions = try container.decodeIfPresent(CursorRenderOptions.self, forKey: .cursorOptions)
        keystrokeOptions = try container.decodeIfPresent(
            KeystrokeRenderOptions.self, forKey: .keystrokeOptions)
        captionOptions = try container.decodeIfPresent(
            CaptionRenderOptions.self, forKey: .captionOptions)
        cameraOverlay = try container.decodeIfPresent(CameraOverlayPlan.self, forKey: .cameraOverlay)
        zoomBlocks = try container.decodeIfPresent([ZoomBlock].self, forKey: .zoomBlocks) ?? []
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
                audioMix: audioMix,
                shouldCrop: shouldCrop,
                cropRect: cropRect,
                quality: quality,
                speed: speed,
                gifOptions: gifOptions,
                cursorOptions: cursorOptions,
                keystrokeOptions: keystrokeOptions,
                captionOptions: captionOptions,
                cameraOverlay: cameraOverlay,
                zoomBlocks: zoomBlocks
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
