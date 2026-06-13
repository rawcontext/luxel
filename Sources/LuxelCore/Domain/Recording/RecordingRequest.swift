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
            displayID: displayID,
            audio: audio,
            videoCodec: videoCodec,
            captureKind: captureKind,
            schedule: schedule,
            timelapse: timelapse
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
