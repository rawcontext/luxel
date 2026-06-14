import Foundation

public enum ExportFormat: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case gif
    case hevc
    case mp4
    case webm
    case apng
    case av1

    public static let appleNativeV1Formats: [ExportFormat] = [.mp4, .hevc, .gif, .apng]
    public static let externalNativeCodecFormats: [ExportFormat] = [.webm, .av1]

    public var isAppleNativeV1Format: Bool {
        Self.appleNativeV1Formats.contains(self)
    }

    public var requiresExternalNativeCodec: Bool {
        switch self {
        case .webm, .av1:
            true
        case .gif, .hevc, .mp4, .apng:
            false
        }
    }

    public var fileExtension: String {
        switch self {
        case .av1, .hevc, .mp4:
            "mp4"
        case .gif:
            "gif"
        case .webm:
            "webm"
        case .apng:
            "apng"
        }
    }

    public var prettyName: String {
        switch self {
        case .gif:
            "GIF"
        case .hevc:
            "MP4 (H265)"
        case .mp4:
            "MP4 (H264)"
        case .av1:
            "MP4 (AV1)"
        case .webm:
            "WebM"
        case .apng:
            "APNG"
        }
    }

    public var dropsAudio: Bool {
        switch self {
        case .gif, .apng:
            true
        case .av1, .hevc, .mp4, .webm:
            false
        }
    }

    public var requiresEvenPixelDimensions: Bool {
        switch self {
        case .av1, .hevc, .mp4, .webm:
            true
        case .gif, .apng:
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
            "Compact"
        case .balanced:
            "Balanced"
        case .high:
            "High"
        case .lossless:
            "Lossless"
        }
    }

    public static func availableQualities(for format: ExportFormat) -> [ExportQuality] {
        switch format {
        case .mp4, .hevc, .gif, .webm, .av1:
            [.compact, .balanced, .high]
        case .apng:
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
        case .mp4, .hevc, .gif, .webm, .av1:
            .balanced
        }
    }

    public func videoBitsPerPixel(for format: ExportFormat) -> Double? {
        switch format {
        case .mp4:
            switch self {
            case .compact:
                0.07
            case .balanced:
                0.12
            case .high:
                0.20
            case .lossless:
                nil
            }
        case .hevc:
            switch self {
            case .compact:
                0.05
            case .balanced:
                0.09
            case .high:
                0.15
            case .lossless:
                nil
            }
        case .gif, .apng, .webm, .av1:
            nil
        }
    }
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
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw ExportModelError.invalidPixelSize
        }

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

public struct FrameRate: Codable, Equatable, Sendable {
    public let framesPerSecond: Int

    public init(_ framesPerSecond: Int) throws {
        guard framesPerSecond > 0 else {
            throw ExportModelError.invalidFrameRate
        }

        self.framesPerSecond = framesPerSecond
    }
}

public struct PlaybackSpeed: Codable, Equatable, Sendable {
    public static let normal = try! PlaybackSpeed(1)

    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, (0.1...10).contains(value) else {
            throw ExportModelError.invalidPlaybackSpeed
        }

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

public struct ExportRequest: Codable, Equatable, Sendable {
    public let inputFileURL: URL
    public let format: ExportFormat
    public let pixelSize: PixelSize
    public let frameRate: FrameRate
    public let timeRange: TimeRange
    public let shouldMute: Bool
    public let audioMix: AudioMixPlan?
    public let shouldCrop: Bool
    public let quality: ExportQuality
    public let speed: PlaybackSpeed
    public let gifOptions: GIFRenderOptions?
    public let cursorOptions: CursorRenderOptions?
    public let keystrokeOptions: KeystrokeRenderOptions?
    public let captionOptions: CaptionRenderOptions?

    public init(
        inputFileURL: URL,
        format: ExportFormat,
        pixelSize: PixelSize,
        frameRate: FrameRate,
        timeRange: TimeRange,
        shouldMute: Bool,
        audioMix: AudioMixPlan? = nil,
        shouldCrop: Bool,
        quality: ExportQuality = .balanced,
        speed: PlaybackSpeed = .normal,
        gifOptions: GIFRenderOptions? = nil,
        cursorOptions: CursorRenderOptions? = nil,
        keystrokeOptions: KeystrokeRenderOptions? = nil,
        captionOptions: CaptionRenderOptions? = nil
    ) {
        self.inputFileURL = inputFileURL
        self.format = format
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.timeRange = timeRange
        self.shouldMute = shouldMute
        self.audioMix = audioMix
        self.shouldCrop = shouldCrop
        self.quality = quality
        self.speed = speed
        self.gifOptions = gifOptions
        self.cursorOptions = cursorOptions
        self.keystrokeOptions = keystrokeOptions
        self.captionOptions = captionOptions
    }

    private enum CodingKeys: String, CodingKey {
        case inputFileURL
        case format
        case pixelSize
        case frameRate
        case timeRange
        case shouldMute
        case audioMix
        case shouldCrop
        case quality
        case speed
        case gifOptions
        case cursorOptions
        case keystrokeOptions
        case captionOptions
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
        shouldCrop = try container.decode(Bool.self, forKey: .shouldCrop)
        quality = try container.decodeIfPresent(ExportQuality.self, forKey: .quality)
            ?? .balanced
        speed = try container.decodeIfPresent(PlaybackSpeed.self, forKey: .speed)
            ?? .normal
        gifOptions = try container.decodeIfPresent(GIFRenderOptions.self, forKey: .gifOptions)
        cursorOptions = try container.decodeIfPresent(CursorRenderOptions.self, forKey: .cursorOptions)
        keystrokeOptions = try container.decodeIfPresent(KeystrokeRenderOptions.self, forKey: .keystrokeOptions)
        captionOptions = try container.decodeIfPresent(CaptionRenderOptions.self, forKey: .captionOptions)
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

    public var outputDuration: TimeInterval {
        timeRange.duration / speed.value
    }

    public func outputFileName(defaultName: String) -> String {
        "\(defaultName).\(format.fileExtension)"
    }
}

public struct PassthroughExportRequest: Codable, Equatable, Sendable {
    public let inputFileURL: URL
    public let outputFileURL: URL
    public let timeRange: TimeRange?

    public init(
        inputFileURL: URL,
        outputFileURL: URL,
        timeRange: TimeRange? = nil
    ) {
        self.inputFileURL = inputFileURL
        self.outputFileURL = outputFileURL
        self.timeRange = timeRange
    }

    public var outputFileName: String {
        outputFileURL.lastPathComponent
    }
}

public struct PassthroughExportResult: Codable, Equatable, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public struct ExportBatch: Codable, Equatable, Sendable {
    public let requests: [ExportRequest]

    public init(_ requests: [ExportRequest]) throws {
        guard let firstRequest = requests.first else {
            throw ExportModelError.emptyExportBatch
        }

        let sourceFileURL = firstRequest.inputFileURL.standardizedFileURL
        guard requests.allSatisfy({ $0.inputFileURL.standardizedFileURL == sourceFileURL }) else {
            throw ExportModelError.mixedExportBatchSources
        }

        let timeRange = firstRequest.timeRange
        guard requests.allSatisfy({ $0.timeRange == timeRange }) else {
            throw ExportModelError.mixedExportBatchTimeRanges
        }

        self.requests = requests
    }
}

public struct ExportBatchProgressSnapshot: Codable, Equatable, Sendable {
    public let jobID: Int
    public let snapshot: ExportProgressSnapshot

    public init(jobID: Int, snapshot: ExportProgressSnapshot) {
        self.jobID = jobID
        self.snapshot = snapshot
    }
}

public enum ExportEstimateConfidence: String, Codable, Equatable, Sendable {
    case exact
    case modeled
    case sampled
}

public struct ExportEstimate: Codable, Equatable, Sendable {
    public let bytes: Int64
    public let confidence: ExportEstimateConfidence

    public init(bytes: Int64, confidence: ExportEstimateConfidence) throws {
        guard bytes >= 0 else {
            throw ExportModelError.invalidEstimateByteCount
        }

        self.bytes = bytes
        self.confidence = confidence
    }
}

public struct ExportPreset: Codable, Equatable, Identifiable, Sendable {
    public static let quickGIFID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    public static let quickMP4ID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    public static let builtInDefaults: [ExportPreset] = {
        do {
            return [
                try ExportPreset(
                    id: quickGIFID,
                    name: "Quick GIF",
                    format: .gif,
                    sizeRule: .maxWidth(960),
                    frameRate: FrameRate(30),
                    destination: .clipboard,
                    postAction: .copyToClipboard
                ),
                try ExportPreset(
                    id: quickMP4ID,
                    name: "Quick MP4",
                    format: .mp4,
                    sizeRule: .original,
                    frameRate: nil,
                    destination: .recordingsDirectory,
                    postAction: .revealInFinder
                )
            ]
        } catch {
            preconditionFailure("Invalid built-in export preset: \(error)")
        }
    }()

    public let id: UUID
    public var name: String
    public var format: ExportFormat
    public var sizeRule: ExportPresetSizeRule
    public var frameRate: FrameRate?
    public var destination: ExportPresetDestination
    public var postAction: ExportPresetPostAction

    public init(
        id: UUID = UUID(),
        name: String,
        format: ExportFormat,
        sizeRule: ExportPresetSizeRule,
        frameRate: FrameRate?,
        destination: ExportPresetDestination,
        postAction: ExportPresetPostAction
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportPresetError.invalidName
        }

        if case .maxWidth(let maxWidth) = sizeRule, maxWidth <= 0 {
            throw ExportPresetError.invalidMaxWidth
        }

        self.id = id
        self.name = name
        self.format = format
        self.sizeRule = sizeRule
        self.frameRate = frameRate
        self.destination = destination
        self.postAction = postAction
    }

    public var effectivePostAction: ExportPresetPostAction {
        if destination == .clipboard {
            return .copyToClipboard
        }

        return postAction
    }

    public func resolvedRequest(source: SourceMedia) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: source.fileURL,
            format: format,
            pixelSize: sizeRule.pixelSize(for: source.pixelSize),
            frameRate: resolvedFrameRate(sourceFrameRate: source.nominalFrameRate),
            timeRange: TimeRange(start: 0, end: source.duration),
            shouldMute: !source.hasAudio,
            shouldCrop: false
        )
    }

    private func resolvedFrameRate(sourceFrameRate: FrameRate) throws -> FrameRate {
        guard let frameRate else {
            return sourceFrameRate
        }

        return try FrameRate(min(frameRate.framesPerSecond, sourceFrameRate.framesPerSecond))
    }
}

public enum ExportPresetSizeRule: Codable, Equatable, Sendable {
    case original
    case preset(EditorSizePreset)
    case maxWidth(Int)

    public func pixelSize(for sourcePixelSize: PixelSize) throws -> PixelSize {
        switch self {
        case .original:
            return sourcePixelSize
        case .preset(let preset):
            return try preset.pixelSize(for: sourcePixelSize)
        case .maxWidth(let maxWidth):
            guard maxWidth > 0 else {
                throw ExportPresetError.invalidMaxWidth
            }

            let scale = min(1, Double(maxWidth) / Double(sourcePixelSize.width))
            return try PixelSize(
                width: max(1, Int((Double(sourcePixelSize.width) * scale).rounded())),
                height: max(1, Int((Double(sourcePixelSize.height) * scale).rounded()))
            )
        }
    }
}

public enum ExportPresetDestination: Codable, Equatable, Sendable {
    case recordingsDirectory
    case folder(URL)
    case clipboard
}

public enum ExportPresetPostAction: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case revealInFinder
    case copyToClipboard
    case notifyWithThumbnail
}

public enum ExportPresetError: Error, Equatable {
    case invalidName
    case invalidMaxWidth
}

public enum ExportProgressPhase: String, Codable, Equatable, Sendable {
    case preparing
    case exporting
    case completed
    case canceled
}

public struct ExportProgressSnapshot: Codable, Equatable, Sendable {
    public let phase: ExportProgressPhase
    public let actionTitle: String
    public let progress: Double

    public init(phase: ExportProgressPhase, actionTitle: String, progress: Double) {
        self.phase = phase
        self.actionTitle = actionTitle
        self.progress = min(max(progress, 0), 1)
    }

    public static func preparing(format: ExportFormat) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .preparing,
            actionTitle: "Preparing \(format.prettyName)",
            progress: 0
        )
    }

    public static func exporting(format: ExportFormat, progress: Double) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .exporting,
            actionTitle: "Exporting \(format.prettyName)",
            progress: progress
        )
    }

    public static func completed(format: ExportFormat) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .completed,
            actionTitle: "Exported \(format.prettyName)",
            progress: 1
        )
    }

    public static func canceled(format: ExportFormat) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .canceled,
            actionTitle: "Canceled \(format.prettyName)",
            progress: 1
        )
    }
}

public enum ExportModelError: Error, Equatable {
    case invalidPixelSize
    case invalidFrameRate
    case invalidPlaybackSpeed
    case invalidTimeRange
    case invalidEstimateByteCount
    case emptyExportBatch
    case mixedExportBatchSources
    case mixedExportBatchTimeRanges
}
