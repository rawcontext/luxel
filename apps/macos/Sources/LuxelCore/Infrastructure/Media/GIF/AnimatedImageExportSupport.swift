import CoreGraphics
import CoreMedia
import Foundation
import ImageIO

enum AnimatedImageIOProperties {
    static func destination(
        format: ExportFormat,
        loopMode: GIFLoopMode = .forever
    ) -> [CFString: Any] {
        switch format {
        case .gif:
            return [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: loopMode.imageIOLoopCount ?? 0
                ]
            ]
        case .apng:
            guard let loopCount = loopMode.imageIOLoopCount else {
                return [:]
            }
            return [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGLoopCount: loopCount
                ]
            ]
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            return [:]
        }
    }

    static func frame(format: ExportFormat, delay: TimeInterval) -> [CFString: Any] {
        switch format {
        case .gif:
            return [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ]
        case .apng:
            return [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: delay,
                    kCGImagePropertyAPNGUnclampedDelayTime: delay
                ]
            ]
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            return [:]
        }
    }
}

extension ExportRequest {
    func animatedCameraPath(sourceFrame: CGImage) throws -> CameraPath? {
        guard !zoomBlocks.isEmpty else {
            return nil
        }
        let mappedBlocks = try timelineMapper.map(zoomBlocks)
        guard !mappedBlocks.isEmpty else {
            return nil
        }
        return try CameraPath(
            blocks: mappedBlocks,
            sourceSize: PixelSize(width: sourceFrame.width, height: sourceFrame.height)
        )
    }

    func animatedCameraTransform(at sourceTime: CMTime, cameraPath: CameraPath?) throws
        -> CameraTransform
    {
        guard let cameraPath,
            let outputTime = timelineMapper.outputTime(forSourceTime: sourceTime.seconds)
        else {
            return .identity
        }
        return try cameraPath.transform(at: outputTime)
    }
}
