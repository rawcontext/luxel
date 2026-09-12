import Foundation

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

        let editPlan = firstRequest.editPlan
        guard requests.allSatisfy({ $0.editPlan == editPlan }) else {
            throw ExportModelError.mixedExportBatchEditPlans
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
                    name: LuxelLocalization.string("Quick GIF"),
                    format: .gif,
                    sizeRule: .maxWidth(960),
                    frameRate: FrameRate(30),
                    destination: .clipboard,
                    postAction: .copyToClipboard
                ),
                try ExportPreset(
                    id: quickMP4ID,
                    name: LuxelLocalization.string("Quick MP4"),
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
            return try sourcePixelSize.scaled(by: scale)
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
    case enhancingAudio
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
            actionTitle: LuxelLocalization.format("Preparing %@", format.prettyName),
            progress: 0
        )
    }

    public static func exporting(format: ExportFormat, progress: Double) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .exporting,
            actionTitle: LuxelLocalization.format("Exporting %@", format.prettyName),
            progress: progress
        )
    }

    public static func enhancingAudio(
        format: ExportFormat,
        progress: Double
    ) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .enhancingAudio,
            actionTitle: LuxelLocalization.string(
                "export.job.enhancingAudio",
                defaultValue: "Enhancing audio…"),
            progress: progress
        )
    }

    public static func completed(format: ExportFormat) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .completed,
            actionTitle: LuxelLocalization.format("Exported %@", format.prettyName),
            progress: 1
        )
    }

    public static func canceled(format: ExportFormat) -> ExportProgressSnapshot {
        ExportProgressSnapshot(
            phase: .canceled,
            actionTitle: LuxelLocalization.format("Canceled %@", format.prettyName),
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
    case mixedExportBatchEditPlans
}
