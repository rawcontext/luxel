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
        sourceCropRect: CaptureRect? = nil,
        zoomBlocks: [ZoomBlock] = []
    ) async throws -> AVVideoComposition {
        let outputSize = CGSize(width: outputPixelSize.width, height: outputPixelSize.height)
        let geometry = try await compositionGeometry(sourceVideoTrack: sourceVideoTrack)
        let spatialCropRect = try spatialPresentationCropRect(
            sourceCropRect,
            presentationSize: geometry.presentationSize
        )
        let layerInstruction = try layerInstruction(
            trackID: compositionVideoTrack.trackID,
            geometry: geometry,
            outputSize: outputSize,
            shouldCrop: shouldCrop,
            spatialCropRect: spatialCropRect,
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
        spatialCropRect: CGRect?,
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
                    spatialCropRect: spatialCropRect,
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
            spatialCropRect: spatialCropRect,
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
        spatialCropRect: CGRect?,
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
                start: sourceCropRect(for: startTransform, geometry: geometry, spatialCropRect: spatialCropRect),
                end: sourceCropRect(for: endTransform, geometry: geometry, spatialCropRect: spatialCropRect)
            ))
            layerConfiguration.addTransformRamp(AVVideoCompositionLayerInstruction.TransformRamp(
                timeRange: rampTimeRange,
                start: renderTransform(
                    geometry: geometry,
                    outputSize: outputSize,
                    shouldCrop: shouldCrop,
                    spatialCropRect: spatialCropRect,
                    cameraTransform: startTransform
                ),
                end: renderTransform(
                    geometry: geometry,
                    outputSize: outputSize,
                    shouldCrop: shouldCrop,
                    spatialCropRect: spatialCropRect,
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
        spatialCropRect: CGRect?,
        cameraTransform: CameraTransform
    ) -> CGAffineTransform {
        let cropRect = presentationCropRect(
            for: cameraTransform.sourceRect,
            presentationSize: geometry.presentationSize,
            spatialCropRect: spatialCropRect
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
        geometry: VideoCompositionGeometry,
        spatialCropRect: CGRect?
    ) -> CGRect {
        let presentationCrop = presentationCropRect(
            for: cameraTransform.sourceRect,
            presentationSize: geometry.presentationSize,
            spatialCropRect: spatialCropRect
        )
        let sourceCrop = presentationCrop
            .applying(geometry.sourceToPresentationTransform.inverted())
            .standardized

        return sourceCrop.intersection(CGRect(origin: .zero, size: geometry.naturalSize))
    }

    private func presentationCropRect(
        for sourceRect: NormalizedRect,
        presentationSize: CGSize,
        spatialCropRect: CGRect?
    ) -> CGRect {
        let baseRect = spatialCropRect ?? CGRect(origin: .zero, size: presentationSize)
        return CGRect(
            x: baseRect.minX + sourceRect.originX * baseRect.width,
            y: baseRect.minY + sourceRect.originY * baseRect.height,
            width: sourceRect.width * baseRect.width,
            height: sourceRect.height * baseRect.height
        )
    }

    private func spatialPresentationCropRect(
        _ cropRect: CaptureRect?,
        presentationSize: CGSize
    ) throws -> CGRect? {
        guard let cropRect else {
            return nil
        }

        let presentationBounds = CGRect(origin: .zero, size: presentationSize)
        let requestedRect = CGRect(
            x: cropRect.originX,
            y: cropRect.originY,
            width: cropRect.width,
            height: cropRect.height
        )
        let clampedRect = requestedRect.intersection(presentationBounds)
        guard !clampedRect.isNull,
              clampedRect.width > 0,
              clampedRect.height > 0 else {
            throw AVFoundationVideoCompositionFactoryError.invalidCropRect
        }

        return clampedRect
    }

    private func outputSeconds(_ time: CMTime, in timeRange: CMTimeRange) -> TimeInterval {
        max(0, CMTimeSubtract(time, timeRange.start).seconds)
    }
}

enum AVFoundationVideoCompositionFactoryError: Error, Equatable {
    case invalidVideoDimensions
    case invalidCropRect
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
