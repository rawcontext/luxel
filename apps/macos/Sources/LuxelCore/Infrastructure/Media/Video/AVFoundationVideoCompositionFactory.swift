import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import QuartzCore

struct AVFoundationVideoCompositionFactory: Sendable {
    func makeVideoComposition(
        sourceVideoTrack: AVAssetTrack,
        compositionVideoTrack: AVCompositionTrack,
        timeRange: CMTimeRange,
        outputPixelSize: PixelSize,
        request: ExportRequest
    ) async throws -> AVVideoComposition {
        try await makeVideoComposition(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: compositionVideoTrack,
            timeRange: timeRange,
            outputPixelSize: outputPixelSize,
            frameRate: request.frameRate,
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            zoomBlocks: EditedTimelineMapper(
                trimRange: request.timeRange,
                editPlan: request.editPlan,
                speed: request.speed
            ).map(request.zoomBlocks),
            keystrokeTimeline: try? KeystrokeSidecarFileLoader().load(
                nextTo: request.inputFileURL
            ),
            keystrokeOptions: request.keystrokeOptions,
            keystrokeTimelineMapper: request.timelineMapper
        )
    }

    func makeVideoComposition(
        sourceVideoTrack: AVAssetTrack,
        compositionVideoTrack: AVCompositionTrack,
        timeRange: CMTimeRange,
        outputPixelSize: PixelSize,
        frameRate: FrameRate,
        shouldCrop: Bool = false,
        sourceCropRect: CaptureRect? = nil,
        zoomBlocks: [ZoomBlock] = [],
        keystrokeTimeline: KeystrokeTimeline? = nil,
        keystrokeOptions: KeystrokeRenderOptions? = nil,
        keystrokeTimelineMapper: EditedTimelineMapper? = nil
    ) async throws -> AVVideoComposition {
        let outputSize = CGSize(width: outputPixelSize.width, height: outputPixelSize.height)
        let geometry = try await compositionGeometry(sourceVideoTrack: sourceVideoTrack)
        let spatialCropRect = try spatialPresentationCropRect(
            sourceCropRect,
            presentationSize: geometry.presentationSize
        )
        let instructionContext = VideoCompositionInstructionContext(
            geometry: geometry,
            outputSize: outputSize,
            shouldCrop: shouldCrop,
            spatialCropRect: spatialCropRect,
            timeRange: timeRange,
            frameRate: frameRate
        )
        let layerInstruction = try layerInstruction(
            trackID: compositionVideoTrack.trackID,
            context: instructionContext,
            zoomBlocks: zoomBlocks
        )
        let instructionConfiguration = AVVideoCompositionInstruction.Configuration(
            layerInstructions: [layerInstruction],
            timeRange: timeRange
        )
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfiguration)
        var compositionConfiguration = AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate.framesPerSecond)),
            instructions: [instruction],
            renderSize: outputSize
        )
        compositionConfiguration.animationTool = await keystrokeAnimationTool(
            outputSize: outputSize,
            timeline: keystrokeTimeline,
            options: keystrokeOptions,
            timelineMapper: keystrokeTimelineMapper
        )
        return AVVideoComposition(configuration: compositionConfiguration)
    }
}

extension AVFoundationVideoCompositionFactory {
    @MainActor
    private func keystrokeAnimationTool(
        outputSize: CGSize,
        timeline: KeystrokeTimeline?,
        options: KeystrokeRenderOptions?,
        timelineMapper: EditedTimelineMapper?
    ) -> AVVideoCompositionCoreAnimationTool? {
        guard let timeline,
            let options,
            let timelineMapper,
            options.isVisible,
            let chips = try? KeystrokeChipPlanner(renderOptions: options)
                .plannedChips(for: timeline),
            !chips.isEmpty
        else {
            return nil
        }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)
        addKeystrokeLayers(
            chips,
            to: parentLayer,
            outputSize: outputSize,
            options: options,
            timelineMapper: timelineMapper
        )

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    @MainActor
    private func addKeystrokeLayers(
        _ chips: [KeystrokeChip],
        to parentLayer: CALayer,
        outputSize: CGSize,
        options: KeystrokeRenderOptions,
        timelineMapper: EditedTimelineMapper
    ) {
        let renderer = KeystrokeChipImageRenderer()
        for chip in chips {
            guard let outputRanges = try? timelineMapper.mapSourceRange(chip.timeRange),
                !outputRanges.isEmpty,
                let image = renderer.image(for: chip, options: options)
            else {
                continue
            }

            let size = CGSize(width: image.width, height: image.height)
            let activeChips = KeystrokeOverlayLayout.activeChips(
                at: chip.timeRange.start,
                in: chips
            )
            let stackIndex = activeChips.firstIndex(of: chip) ?? 0
            var origin = KeystrokeOverlayLayout.origin(
                overlaySize: size,
                frameSize: outputSize,
                anchor: options.anchor
            )
            let stackOffset = CGFloat(stackIndex) * (size.height + 8)
            switch options.anchor {
            case .bottomLeft, .bottomCenter, .bottomRight:
                origin.y += stackOffset
            case .topLeft, .topCenter, .topRight:
                origin.y -= stackOffset
            }
            for outputRange in outputRanges {
                let layer = CALayer()
                layer.contents = image
                layer.contentsGravity = .resizeAspect
                layer.frame = CGRect(origin: origin, size: size)
                layer.opacity = 0

                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [0, 1, 1, 0]
                animation.keyTimes = [0, 0.01, 0.82, 1]
                animation.beginTime = AVCoreAnimationBeginTimeAtZero + outputRange.start
                animation.duration = max(0.01, outputRange.duration)
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: "keystrokeVisibility")
                parentLayer.addSublayer(layer)
            }
        }
    }

    private func compositionGeometry(sourceVideoTrack: AVAssetTrack) async throws
        -> VideoCompositionGeometry {
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
        context: VideoCompositionInstructionContext,
        zoomBlocks: [ZoomBlock]
    ) throws -> AVVideoCompositionLayerInstruction {
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(trackID: trackID)

        guard !zoomBlocks.isEmpty else {
            layerConfiguration.setTransform(
                renderTransform(
                    geometry: context.geometry,
                    outputSize: context.outputSize,
                    shouldCrop: context.shouldCrop,
                    spatialCropRect: context.spatialCropRect,
                    cameraTransform: .identity
                ),
                at: .zero
            )
            return AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        }

        let cameraPath = try CameraPath(
            blocks: zoomBlocks,
            sourceSize: context.geometry.sourcePixelSize
        )
        try addCameraRamps(
            to: &layerConfiguration,
            cameraPath: cameraPath,
            context: context
        )

        return AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
    }

    private func addCameraRamps(
        to layerConfiguration: inout AVVideoCompositionLayerInstruction.Configuration,
        cameraPath: CameraPath,
        context: VideoCompositionInstructionContext
    ) throws {
        let frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(context.frameRate.framesPerSecond)
        )
        var currentTime = context.timeRange.start

        while CMTimeCompare(currentTime, context.timeRange.end) < 0 {
            let proposedEndTime = CMTimeAdd(currentTime, frameDuration)
            let nextTime =
                CMTimeCompare(proposedEndTime, context.timeRange.end) > 0
                ? context.timeRange.end : proposedEndTime
            let rampTimeRange = CMTimeRange(
                start: currentTime,
                duration: CMTimeSubtract(nextTime, currentTime)
            )
            try addCameraRamp(
                to: &layerConfiguration,
                cameraPath: cameraPath,
                context: context,
                timeRange: rampTimeRange
            )

            currentTime = nextTime
        }
    }

    func renderTransform(
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

    func sourceCropRect(
        for cameraTransform: CameraTransform,
        geometry: VideoCompositionGeometry,
        spatialCropRect: CGRect?
    ) -> CGRect {
        let presentationCrop = presentationCropRect(
            for: cameraTransform.sourceRect,
            presentationSize: geometry.presentationSize,
            spatialCropRect: spatialCropRect
        )
        let sourceCrop =
            presentationCrop
            .applying(geometry.sourceToPresentationTransform.inverted())
            .standardized

        return sourceCrop.intersection(CGRect(origin: .zero, size: geometry.naturalSize))
    }

    func presentationCropRect(
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
            clampedRect.height > 0
        else {
            throw AVFoundationVideoCompositionFactoryError.invalidCropRect
        }

        return clampedRect
    }

    func outputSeconds(_ time: CMTime, in timeRange: CMTimeRange) -> TimeInterval {
        max(0, CMTimeSubtract(time, timeRange.start).seconds)
    }
}

enum AVFoundationVideoCompositionFactoryError: Error, Equatable {
    case invalidVideoDimensions
    case invalidCropRect
}

struct VideoCompositionGeometry {
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

struct VideoCompositionInstructionContext {
    let geometry: VideoCompositionGeometry
    let outputSize: CGSize
    let shouldCrop: Bool
    let spatialCropRect: CGRect?
    let timeRange: CMTimeRange
    let frameRate: FrameRate
}
