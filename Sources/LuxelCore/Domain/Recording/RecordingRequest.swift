import Foundation

public enum RecordingAudioMode: Codable, Equatable, Sendable {
    case none
    case system
    case microphone(deviceID: String?)
    case systemAndMicrophone(deviceID: String?)

    public var capturesSystemAudio: Bool {
        switch self {
        case .system, .systemAndMicrophone:
            true
        case .none, .microphone:
            false
        }
    }

    public var capturesMicrophone: Bool {
        switch self {
        case .microphone, .systemAndMicrophone:
            true
        case .none, .system:
            false
        }
    }

    public var microphoneDeviceID: String? {
        switch self {
        case .microphone(let deviceID), .systemAndMicrophone(let deviceID):
            deviceID
        case .none, .system:
            nil
        }
    }
}

public struct RecordingRequest: Codable, Equatable, Sendable {
    public let target: CaptureTarget
    public let outputFileURL: URL
    public let pixelSize: PixelSize
    public let frameRate: FrameRate
    public let showCursor: Bool
    public let highlightClicks: Bool
    public let captureKeystrokes: Bool
    public let camera: CameraRecordingOptions?
    public let audio: RecordingAudioMode
    public let videoCodec: RecordingCodec
    public let captureKind: QuickCaptureKind
    public let schedule: RecordingSchedule?
    public let timelapse: TimelapseOptions?

    public init(
        target: CaptureTarget,
        outputFileURL: URL,
        pixelSize: PixelSize,
        frameRate: FrameRate,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        captureKeystrokes: Bool = false,
        camera: CameraRecordingOptions? = nil,
        audio: RecordingAudioMode = .none,
        videoCodec: RecordingCodec = .h264,
        captureKind: QuickCaptureKind = .standard,
        schedule: RecordingSchedule? = nil,
        timelapse: TimelapseOptions? = nil
    ) {
        self.target = target
        self.outputFileURL = outputFileURL
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.showCursor = showCursor
        self.highlightClicks = highlightClicks
        self.captureKeystrokes = captureKeystrokes
        self.camera = camera
        self.audio = timelapse == nil ? audio : .none
        self.videoCodec = videoCodec
        self.captureKind = captureKind
        self.schedule = schedule
        self.timelapse = timelapse
    }

    public var recordingOptions: RecordingOptions {
        RecordingOptions(
            frameRate: frameRate.framesPerSecond,
            captureRect: captureRect,
            showCursor: showCursor,
            highlightClicks: highlightClicks,
            captureKeystrokes: captureKeystrokes,
            camera: camera,
            displayID: displayID,
            audio: audio,
            videoCodec: videoCodec,
            captureKind: captureKind,
            schedule: schedule,
            timelapse: timelapse
        )
    }

    public func replacingOutputFileURL(_ outputFileURL: URL) -> RecordingRequest {
        RecordingRequest(
            target: target,
            outputFileURL: outputFileURL,
            pixelSize: pixelSize,
            frameRate: frameRate,
            showCursor: showCursor,
            highlightClicks: highlightClicks,
            captureKeystrokes: captureKeystrokes,
            camera: camera,
            audio: audio,
            videoCodec: videoCodec,
            captureKind: captureKind,
            schedule: schedule,
            timelapse: timelapse
        )
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case outputFileURL
        case pixelSize
        case frameRate
        case showCursor
        case highlightClicks
        case captureKeystrokes
        case camera
        case audio
        case videoCodec
        case captureKind
        case schedule
        case timelapse
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        try self.init(
            target: container.decode(CaptureTarget.self, forKey: .target),
            outputFileURL: container.decode(URL.self, forKey: .outputFileURL),
            pixelSize: container.decode(PixelSize.self, forKey: .pixelSize),
            frameRate: container.decode(FrameRate.self, forKey: .frameRate),
            showCursor: container.decodeIfPresent(Bool.self, forKey: .showCursor) ?? true,
            highlightClicks: container.decodeIfPresent(Bool.self, forKey: .highlightClicks) ?? false,
            captureKeystrokes: container.decodeIfPresent(Bool.self, forKey: .captureKeystrokes) ?? false,
            camera: container.decodeIfPresent(CameraRecordingOptions.self, forKey: .camera),
            audio: container.decodeIfPresent(RecordingAudioMode.self, forKey: .audio) ?? .none,
            videoCodec: container.decodeIfPresent(RecordingCodec.self, forKey: .videoCodec) ?? .h264,
            captureKind: container.decodeIfPresent(QuickCaptureKind.self, forKey: .captureKind) ?? .standard,
            schedule: container.decodeIfPresent(RecordingSchedule.self, forKey: .schedule),
            timelapse: container.decodeIfPresent(TimelapseOptions.self, forKey: .timelapse)
        )
    }

    private var captureRect: CaptureRect? {
        if case .area(_, let rect) = target {
            return rect
        }

        return nil
    }

    private var displayID: DisplayID? {
        switch target {
        case .display(let displayID), .area(let displayID, _):
            displayID
        case .window:
            nil
        }
    }
}
