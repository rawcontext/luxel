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
        shouldCrop: Bool,
        zoomBlocks: [ZoomBlock] = []
    ) async throws -> AVVideoComposition {
        let outputSize = CGSize(width: outputPixelSize.width, height: outputPixelSize.height)
        let geometry = try await compositionGeometry(sourceVideoTrack: sourceVideoTrack)
        let layerInstruction = try layerInstruction(
            trackID: compositionVideoTrack.trackID,
            geometry: geometry,
            outputSize: outputSize,
            shouldCrop: shouldCrop,
            timeRange: timeRange,
            frameRate: frameRate,
            zoomBlocks: zoomBlocks
        )
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

    private func compositionGeometry(sourceVideoTrack: AVAssetTrack) async throws -> VideoCompositionGeometry {
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

        return VideoCompositionGeometry(
            naturalSize: naturalSize,
            sourceToPresentationTransform: preferredTransform.concatenating(
                CGAffineTransform(
                    translationX: -transformedRect.origin.x,
                    y: -transformedRect.origin.y
                )
            ),
            presentationSize: presentationSize
        )
    }

    private func layerInstruction(
        trackID: CMPersistentTrackID,
        geometry: VideoCompositionGeometry,
        outputSize: CGSize,
        shouldCrop: Bool,
        timeRange: CMTimeRange,
        frameRate: FrameRate,
        zoomBlocks: [ZoomBlock]
    ) throws -> AVVideoCompositionLayerInstruction {
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(trackID: trackID)

        guard !zoomBlocks.isEmpty else {
            layerConfiguration.setTransform(
                renderTransform(
                    geometry: geometry,
                    outputSize: outputSize,
                    shouldCrop: shouldCrop,
                    cameraTransform: .identity
                ),
                at: .zero
            )
            return AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        }

        let cameraPath = try CameraPath(
            blocks: zoomBlocks,
            sourceSize: geometry.sourcePixelSize
        )
        try addCameraRamps(
            to: &layerConfiguration,
            cameraPath: cameraPath,
            geometry: geometry,
            outputSize: outputSize,
            shouldCrop: shouldCrop,
            timeRange: timeRange,
            frameRate: frameRate
        )

        return AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
    }

    private func addCameraRamps(
        to layerConfiguration: inout AVVideoCompositionLayerInstruction.Configuration,
        cameraPath: CameraPath,
        geometry: VideoCompositionGeometry,
        outputSize: CGSize,
        shouldCrop: Bool,
        timeRange: CMTimeRange,
        frameRate: FrameRate
    ) throws {
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.framesPerSecond))
        var currentTime = timeRange.start

        while CMTimeCompare(currentTime, timeRange.end) < 0 {
            let proposedEndTime = CMTimeAdd(currentTime, frameDuration)
            let nextTime = CMTimeCompare(proposedEndTime, timeRange.end) > 0 ? timeRange.end : proposedEndTime
            let rampTimeRange = CMTimeRange(
                start: currentTime,
                duration: CMTimeSubtract(nextTime, currentTime)
            )
            let startTransform = try cameraPath.transform(at: outputSeconds(currentTime, in: timeRange))
            let endTransform = try cameraPath.transform(at: outputSeconds(nextTime, in: timeRange))

            layerConfiguration.addCropRectangleRamp(AVVideoCompositionLayerInstruction.CropRectangleRamp(
                timeRange: rampTimeRange,
                start: sourceCropRect(for: startTransform, geometry: geometry),
                end: sourceCropRect(for: endTransform, geometry: geometry)
            ))
            layerConfiguration.addTransformRamp(AVVideoCompositionLayerInstruction.TransformRamp(
                timeRange: rampTimeRange,
                start: renderTransform(
                    geometry: geometry,
                    outputSize: outputSize,
                    shouldCrop: shouldCrop,
                    cameraTransform: startTransform
                ),
                end: renderTransform(
                    geometry: geometry,
                    outputSize: outputSize,
                    shouldCrop: shouldCrop,
                    cameraTransform: endTransform
                )
            ))

            currentTime = nextTime
        }
    }

    private func renderTransform(
        geometry: VideoCompositionGeometry,
        outputSize: CGSize,
        shouldCrop: Bool,
        cameraTransform: CameraTransform
    ) -> CGAffineTransform {
        let cropRect = presentationCropRect(
            for: cameraTransform.sourceRect,
            presentationSize: geometry.presentationSize
        )
        let widthScale = outputSize.width / cropRect.width
        let heightScale = outputSize.height / cropRect.height
        let scale = shouldCrop ? max(widthScale, heightScale) : min(widthScale, heightScale)
        let scaledSize = CGSize(
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        let translation = CGSize(
            width: (outputSize.width - scaledSize.width) / 2,
            height: (outputSize.height - scaledSize.height) / 2
        )

        return geometry.sourceToPresentationTransform
            .concatenating(CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(
                CGAffineTransform(
                    translationX: translation.width,
                    y: translation.height
                )
            )
    }

    private func sourceCropRect(
        for cameraTransform: CameraTransform,
        geometry: VideoCompositionGeometry
    ) -> CGRect {
        let presentationCrop = presentationCropRect(
            for: cameraTransform.sourceRect,
            presentationSize: geometry.presentationSize
        )
        let sourceCrop = presentationCrop
            .applying(geometry.sourceToPresentationTransform.inverted())
            .standardized

        return sourceCrop.intersection(CGRect(origin: .zero, size: geometry.naturalSize))
    }

    private func presentationCropRect(
        for sourceRect: NormalizedRect,
        presentationSize: CGSize
    ) -> CGRect {
        CGRect(
            x: sourceRect.x * presentationSize.width,
            y: sourceRect.y * presentationSize.height,
            width: sourceRect.width * presentationSize.width,
            height: sourceRect.height * presentationSize.height
        )
    }

    private func outputSeconds(_ time: CMTime, in timeRange: CMTimeRange) -> TimeInterval {
        max(0, CMTimeSubtract(time, timeRange.start).seconds)
    }
}

enum AVFoundationVideoCompositionFactoryError: Error, Equatable {
    case invalidVideoDimensions
}

private struct VideoCompositionGeometry {
    let naturalSize: CGSize
    let sourceToPresentationTransform: CGAffineTransform
    let presentationSize: CGSize

    var sourcePixelSize: PixelSize {
        get throws {
            try PixelSize(
                width: max(1, Int(presentationSize.width.rounded())),
                height: max(1, Int(presentationSize.height.rounded()))
            )
        }
    }
}
