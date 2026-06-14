import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

struct AVFoundationVideoCompositionFactory: Sendable {
    func makeVideoComposition(
        sourceVideoTrack: AVAssetTrack,
        compositionVideoTrack: AVCompositionTrack,
        timeRange: CMTimeRange,
        outputPixelSize: PixelSize,
        frameRate: FrameRate,
        shouldCrop: Bool
    ) async throws -> AVVideoComposition {
        let outputSize = CGSize(width: outputPixelSize.width, height: outputPixelSize.height)
        let transform = try await renderTransform(
            sourceVideoTrack: sourceVideoTrack,
            outputSize: outputSize,
            shouldCrop: shouldCrop
        )
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(
            trackID: compositionVideoTrack.trackID
        )
        layerConfiguration.setTransform(transform, at: .zero)

        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        let instructionConfiguration = AVVideoCompositionInstruction.Configuration(
            layerInstructions: [layerInstruction],
            timeRange: timeRange
        )
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfiguration)
        let compositionConfiguration = AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate.framesPerSecond)),
            instructions: [instruction],
            renderSize: outputSize
        )

        return AVVideoComposition(configuration: compositionConfiguration)
    }

    private func renderTransform(
        sourceVideoTrack: AVAssetTrack,
        outputSize: CGSize,
        shouldCrop: Bool
    ) async throws -> CGAffineTransform {
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let presentationSize = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )

        guard presentationSize.width > 0, presentationSize.height > 0 else {
            throw AVFoundationVideoCompositionFactoryError.invalidVideoDimensions
        }

        let widthScale = outputSize.width / presentationSize.width
        let heightScale = outputSize.height / presentationSize.height
        let scale = shouldCrop ? max(widthScale, heightScale) : min(widthScale, heightScale)
        let scaledSize = CGSize(
            width: presentationSize.width * scale,
            height: presentationSize.height * scale
        )
        let translation = CGSize(
            width: (outputSize.width - scaledSize.width) / 2,
            height: (outputSize.height - scaledSize.height) / 2
        )

        return preferredTransform
            .concatenating(
                CGAffineTransform(
                    translationX: -transformedRect.origin.x,
                    y: -transformedRect.origin.y
                )
            )
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(
                CGAffineTransform(
                    translationX: translation.width,
                    y: translation.height
                )
            )
    }
}

enum AVFoundationVideoCompositionFactoryError: Error, Equatable {
    case invalidVideoDimensions
}
