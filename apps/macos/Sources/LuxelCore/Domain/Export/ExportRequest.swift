import Foundation

public struct ExportRequest: Codable, Equatable, Sendable {
    public let inputFileURL: URL
    public let format: ExportFormat
    public let pixelSize: PixelSize
    public let frameRate: FrameRate
    public let timeRange: TimeRange
    public let shouldMute: Bool
    public let audioMix: AudioMixPlan?
    public let studioVoiceEnabled: Bool
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
        inputFileURL: URL,
        format: ExportFormat,
        pixelSize: PixelSize,
        frameRate: FrameRate,
        timeRange: TimeRange,
        shouldMute: Bool,
        audioMix: AudioMixPlan? = nil,
        studioVoiceEnabled: Bool = false,
        shouldCrop: Bool,
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
        self.inputFileURL = inputFileURL
        self.format = format
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.timeRange = timeRange
        self.shouldMute = shouldMute
        self.audioMix = audioMix
        self.studioVoiceEnabled = studioVoiceEnabled
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
        case inputFileURL
        case format
        case pixelSize
        case frameRate
        case timeRange
        case shouldMute
        case audioMix
        case studioVoiceEnabled
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
        inputFileURL = try container.decode(URL.self, forKey: .inputFileURL)
        format = try container.decode(ExportFormat.self, forKey: .format)
        pixelSize = try container.decode(PixelSize.self, forKey: .pixelSize)
        frameRate = try container.decode(FrameRate.self, forKey: .frameRate)
        timeRange = try container.decode(TimeRange.self, forKey: .timeRange)
        shouldMute = try container.decode(Bool.self, forKey: .shouldMute)
        audioMix = try container.decodeIfPresent(AudioMixPlan.self, forKey: .audioMix)
        studioVoiceEnabled = try container.decodeIfPresent(Bool.self, forKey: .studioVoiceEnabled) ?? false
        shouldCrop = try container.decode(Bool.self, forKey: .shouldCrop)
        cropRect = try container.decodeIfPresent(CaptureRect.self, forKey: .cropRect)
        quality = try container.decodeIfPresent(ExportQuality.self, forKey: .quality) ?? .balanced
        speed = try container.decodeIfPresent(PlaybackSpeed.self, forKey: .speed) ?? .normal
        gifOptions = try container.decodeIfPresent(GIFRenderOptions.self, forKey: .gifOptions)
        cursorOptions = try container.decodeIfPresent(CursorRenderOptions.self, forKey: .cursorOptions)
        keystrokeOptions = try container.decodeIfPresent(
            KeystrokeRenderOptions.self,
            forKey: .keystrokeOptions
        )
        captionOptions = try container.decodeIfPresent(
            CaptionRenderOptions.self,
            forKey: .captionOptions
        )
        cameraOverlay = try container.decodeIfPresent(CameraOverlayPlan.self, forKey: .cameraOverlay)
        zoomBlocks = try container.decodeIfPresent([ZoomBlock].self, forKey: .zoomBlocks) ?? []
    }

    public var resolvedQuality: ExportQuality {
        quality.isAvailable(for: format) ? quality : ExportQuality.defaultQuality(for: format)
    }

    public var outputPixelSize: PixelSize {
        get throws {
            if format.requiresEvenPixelDimensions {
                return try pixelSize.roundedToEvenDimensions
            }
            return pixelSize
        }
    }

    public var outputShouldMute: Bool {
        shouldMute || audioMix?.isMuted == true || format.dropsAudio
    }

    public var shouldApplyStudioVoice: Bool {
        studioVoiceEnabled && !outputShouldMute && !format.dropsAudio
    }

    public var requiresAudioPreparation: Bool {
        !outputShouldMute && !format.dropsAudio
            && (shouldApplyStudioVoice || audioMix != nil)
    }

    public var outputDuration: TimeInterval {
        timeRange.duration / speed.value
    }

    public func outputFileName(defaultName: String) -> String {
        "\(defaultName).\(format.fileExtension)"
    }
}
