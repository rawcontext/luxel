import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct AVFoundationFrameGrabber: FrameGrabber, Sendable {
    private let imageEncoder: FrameGrabPNGEncoder

    public init(imageEncoder: FrameGrabPNGEncoder = FrameGrabPNGEncoder()) {
        self.imageEncoder = imageEncoder
    }

    public func grab(_ request: FrameGrabRequest) async throws -> FrameGrabImageData {
        let asset = AVURLAsset(url: request.sourceFileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sourceFrame = try await generator.image(
            at: CMTime(seconds: request.time, preferredTimescale: 600)
        ).image
        let frame = try crop(sourceFrame, to: request.cropRect)
        let data = try imageEncoder.encode(frame)

        return try FrameGrabImageData(
            data: data,
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
              rect.maxY <= CGFloat(image.height)
        else {
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
    case encodingFailed
}

public struct FrameGrabPNGEncoder: Sendable {
    public init() {}

    public func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw AVFoundationFrameGrabberError.encodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw AVFoundationFrameGrabberError.encodingFailed
        }

        return data as Data
    }
}
