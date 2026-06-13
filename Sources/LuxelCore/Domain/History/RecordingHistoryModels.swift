import Foundation

public struct PastRecording: Codable, Equatable, Sendable {
    public let fileURL: URL
    public let name: String
    public let date: Date

    public init(fileURL: URL, name: String, date: Date) {
        self.fileURL = fileURL
        self.name = name
        self.date = date
    }
}

public struct ActiveRecording: Codable, Equatable, Sendable {
    public let fileURL: URL
    public let name: String
    public let date: Date
    public let options: RecordingOptions

    public init(fileURL: URL, name: String, date: Date, options: RecordingOptions) {
        self.fileURL = fileURL
        self.name = name
        self.date = date
        self.options = options
    }

    public var pastRecording: PastRecording {
        PastRecording(fileURL: fileURL, name: name, date: date)
    }
}

public struct RecordingOptions: Codable, Equatable, Sendable {
    public let frameRate: Int
    public let captureRect: CaptureRect?
    public let showCursor: Bool
    public let highlightClicks: Bool
    public let displayID: DisplayID?
    public let audio: RecordingAudioMode
    public let videoCodec: RecordingCodec
    public let captureKind: QuickCaptureKind

    public init(
        frameRate: Int,
        captureRect: CaptureRect? = nil,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        displayID: DisplayID? = nil,
        audio: RecordingAudioMode = .none,
        videoCodec: RecordingCodec = .h264,
        captureKind: QuickCaptureKind = .standard
    ) {
        self.frameRate = frameRate
        self.captureRect = captureRect
        self.showCursor = showCursor
        self.highlightClicks = highlightClicks
        self.displayID = displayID
        self.audio = audio
        self.videoCodec = videoCodec
        self.captureKind = captureKind
    }

    private enum CodingKeys: String, CodingKey {
        case frameRate
        case captureRect
        case showCursor
        case highlightClicks
        case displayID
        case audio
        case videoCodec
        case captureKind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        frameRate = try container.decode(Int.self, forKey: .frameRate)
        captureRect = try container.decodeIfPresent(CaptureRect.self, forKey: .captureRect)
        showCursor = try container.decodeIfPresent(Bool.self, forKey: .showCursor)
            ?? true
        highlightClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightClicks)
            ?? false
        displayID = try container.decodeIfPresent(DisplayID.self, forKey: .displayID)
        audio = try container.decodeIfPresent(RecordingAudioMode.self, forKey: .audio)
            ?? .none
        videoCodec = try container.decodeIfPresent(RecordingCodec.self, forKey: .videoCodec)
            ?? .h264
        captureKind = try container.decodeIfPresent(QuickCaptureKind.self, forKey: .captureKind)
            ?? .standard
    }
}

public enum RecordingCodec: String, Codable, Equatable, Sendable {
    case h264
    case hevc
    case proRes422
    case proRes4444
}

public enum MediaProbeResult: Equatable, Sendable {
    case playable
    case corrupt(reason: String)
}

public enum CorruptRecordingRecoveryKind: Equatable, Sendable {
    case knownRepairable
    case unknown
}

public struct CorruptRecordingDiagnostic: Codable, Equatable, Sendable {
    public let fileURL: URL
    public let reason: String
    public let recordedAt: Date

    public init(fileURL: URL, reason: String, recordedAt: Date) {
        self.fileURL = fileURL
        self.reason = reason
        self.recordedAt = recordedAt
    }
}

public struct CorruptRecordingClassifier: Sendable {
    private let knownRepairableReasons: [String]

    public init(knownRepairableReasons: [String] = Self.defaultKnownRepairableReasons) {
        self.knownRepairableReasons = knownRepairableReasons
    }

    public func recoveryKind(for reason: String) -> CorruptRecordingRecoveryKind {
        let normalizedReason = reason.lowercased()

        if knownRepairableReasons.contains(where: { normalizedReason.contains($0.lowercased()) }) {
            return .knownRepairable
        }

        return .unknown
    }

    public static let defaultKnownRepairableReasons = [
        "moov atom not found"
    ]
}

public enum RecordingRecoveryResult: Equatable, Sendable {
    case none
    case playable(PastRecording)
    case knownCorrupt(fileURL: URL, reason: String)
    case unknownCorrupt(fileURL: URL, reason: String)
}
