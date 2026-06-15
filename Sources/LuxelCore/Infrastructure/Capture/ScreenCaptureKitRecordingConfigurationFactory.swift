import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

public struct ScreenRecordingConfigurationFactory: Sendable {
    public init() {}

    public func makeStreamConfiguration(for request: RecordingRequest) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = size_t(request.pixelSize.width)
        configuration.height = size_t(request.pixelSize.height)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(request.frameRate.framesPerSecond)
        )
        configuration.showsCursor = request.showCursor
        configuration.showMouseClicks = request.highlightClicks
        configuration.capturesAudio = request.audio.capturesSystemAudio
        configuration.captureMicrophone = request.audio.capturesMicrophone
        configuration.microphoneCaptureDeviceID = request.audio.microphoneDeviceID
        configuration.excludesCurrentProcessAudio = request.audio.capturesSystemAudio
        configuration.queueDepth = 8

        if case .area(_, let rect) = request.target {
            configuration.sourceRect = CGRect(
                x: rect.originX,
                y: rect.originY,
                width: rect.width,
                height: rect.height
            )
        }

        return configuration
    }

    public func makeRecordingOutputConfiguration(
        for request: RecordingRequest,
        outputFileURL: URL? = nil
    ) -> SCRecordingOutputConfiguration {
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = outputFileURL ?? request.outputFileURL
        configuration.outputFileType = .mp4
        configuration.videoCodecType = request.videoCodec.avVideoCodecType
        return configuration
    }
}

private extension RecordingCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .h264:
            .h264
        case .hevc:
            .hevc
        case .proRes422:
            .proRes422
        case .proRes4444:
            .proRes4444
        }
    }
}
