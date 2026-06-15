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
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
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
}
