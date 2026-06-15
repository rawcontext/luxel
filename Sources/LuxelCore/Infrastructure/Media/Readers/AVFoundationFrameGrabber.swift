import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

public struct AVFoundationFrameGrabber: FrameGrabber, Sendable {
    private let imageEncoder: ImageIOStillImageEncoder

    public init(imageEncoder: ImageIOStillImageEncoder = ImageIOStillImageEncoder()) {
        self.imageEncoder = imageEncoder
    }

    public func grab(_ request: FrameGrabRequest) async throws -> ImageData {
        let asset = AVURLAsset(url: request.sourceFileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sourceFrame = try await generator.image(
            at: CMTime(seconds: request.time, preferredTimescale: 600)
        ).image
        let frame = try crop(sourceFrame, to: request.cropRect)
        let data = try imageEncoder.encode(frame, format: request.format)

        return try ImageData(
            data: data,
            format: request.format,
            pixelSize: PixelSize(width: frame.width, height: frame.height)
        )
    }

    private func crop(_ image: CGImage, to cropRect: CaptureRect?) throws -> CGImage {
        guard let cropRect else {
            return image
        }

        let rect = CGRect(
            x: cropRect.originX,
            y: cropRect.originY,
            width: cropRect.width,
            height: cropRect.height
        )
        guard rect.minX >= 0,
              rect.minY >= 0,
              rect.maxX <= CGFloat(image.width),
              rect.maxY <= CGFloat(image.height) else {
            throw AVFoundationFrameGrabberError.cropOutsideFrame
        }

        guard let croppedImage = image.cropping(to: rect) else {
            throw AVFoundationFrameGrabberError.cannotCropFrame
        }

        return croppedImage
    }
}

public enum AVFoundationFrameGrabberError: Error, Equatable {
    case cropOutsideFrame
    case cannotCropFrame
}
