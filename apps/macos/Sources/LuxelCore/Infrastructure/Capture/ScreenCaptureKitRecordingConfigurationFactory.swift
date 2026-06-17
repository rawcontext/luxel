import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public struct ScreenRecordingConfigurationFactory: Sendable {
    public init() {}

    func requestByResolvingCaptureGeometry(
        _ request: RecordingRequest,
        contentRect: CGRect,
        pointPixelScale: Float
    ) -> RecordingRequest {
        guard case .window = request.target,
              let pixelSize = nativePixelSize(contentRect: contentRect, pointPixelScale: pointPixelScale) else {
            return request
        }

        return request.replacingPixelSize(pixelSize)
    }

    public func makeStreamConfiguration(
        for request: RecordingRequest,
        pointPixelScale: Float = 1
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let pixelSize = (try? request.pixelSize.roundedToEvenDimensions) ?? request.pixelSize
        configuration.width = size_t(pixelSize.width)
        configuration.height = size_t(pixelSize.height)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(request.frameRate.framesPerSecond)
        )
        configuration.showsCursor = request.showCursor
        configuration.showMouseClicks = request.highlightClicks
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.capturesAudio = request.audio.capturesSystemAudio
        configuration.captureMicrophone = request.audio.capturesMicrophone
        configuration.microphoneCaptureDeviceID = request.audio.microphoneDeviceID
        configuration.excludesCurrentProcessAudio = request.audio.capturesSystemAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.queueDepth = 8

        if case .area(_, let rect) = request.target {
            configuration.sourceRect = sourceRect(from: rect, pointPixelScale: pointPixelScale)
        }

        if case .window = request.target {
            configuration.scalesToFit = true
        }

        return configuration
    }

    private func sourceRect(from rect: CaptureRect, pointPixelScale: Float) -> CGRect {
        let pointScale = max(CGFloat(pointPixelScale), 1)
        return CGRect(
            x: CGFloat(rect.originX) / pointScale,
            y: CGFloat(rect.originY) / pointScale,
            width: CGFloat(rect.width) / pointScale,
            height: CGFloat(rect.height) / pointScale
        )
    }

    private func nativePixelSize(contentRect: CGRect, pointPixelScale: Float) -> PixelSize? {
        let pointScale = max(CGFloat(pointPixelScale), 1)
        let width = Int((contentRect.width * pointScale).rounded())
        let height = Int((contentRect.height * pointScale).rounded())

        return try? PixelSize(width: max(width, 1), height: max(height, 1))
    }
}
