import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

public struct AVFoundationMediaExporter: MediaExporter, Sendable {
    private let planFactory: AVFoundationExportPlanFactory

    public init(planFactory: AVFoundationExportPlanFactory = AVFoundationExportPlanFactory()) {
        self.planFactory = planFactory
    }

    public func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        let plan = try planFactory.makePlan(for: request, outputFileURL: outputFileURL)
        let asset = AVURLAsset(url: plan.inputFileURL)
        let sourceVideoTrack = try await firstVideoTrack(in: asset)
        let composition = AVMutableComposition()
        let compositionTimeRange = CMTimeRange(start: .zero, duration: plan.timeRange.duration)
        let compositionVideoTrack = try addVideoTrack(
            to: composition,
            from: sourceVideoTrack,
            sourceTimeRange: plan.timeRange
        )

        if !plan.shouldMute {
            try await addAudioTracks(to: composition, from: asset, sourceTimeRange: plan.timeRange)
        }

        let exportSession = try makeExportSession(for: composition, plan: plan)
        exportSession.videoComposition = try await makeVideoComposition(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: compositionVideoTrack,
            timeRange: compositionTimeRange,
            outputPixelSize: plan.outputPixelSize,
            frameRate: request.frameRate,
            shouldCrop: request.shouldCrop
        )
        exportSession.timeRange = compositionTimeRange
        exportSession.shouldOptimizeForNetworkUse = true

        try? FileManager.default.removeItem(at: plan.outputFileURL)

        do {
            try await exportSession.export(to: plan.outputFileURL, as: plan.outputFileType)
        } catch {
            try? FileManager.default.removeItem(at: plan.outputFileURL)
            throw error
        }

        return ExportedMedia(
            fileURL: plan.outputFileURL,
            format: request.format,
            pixelSize: plan.outputPixelSize,
            shouldMute: plan.shouldMute
        )
    }

    private func firstVideoTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AVFoundationMediaExporterError.missingVideoTrack
        }

        return videoTrack
    }

    private func addVideoTrack(
        to composition: AVMutableComposition,
        from sourceVideoTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange
    ) throws -> AVMutableCompositionTrack {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AVFoundationMediaExporterError.cannotCreateVideoTrack
        }

        try videoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: .zero)
        return videoTrack
    }

    private func addAudioTracks(
        to composition: AVMutableComposition,
        from asset: AVURLAsset,
        sourceTimeRange: CMTimeRange
    ) async throws {
        for sourceAudioTrack in try await asset.loadTracks(withMediaType: .audio) {
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw AVFoundationMediaExporterError.cannotCreateAudioTrack
            }

            try audioTrack.insertTimeRange(sourceTimeRange, of: sourceAudioTrack, at: .zero)
        }
    }

    private func makeExportSession(
        for composition: AVMutableComposition,
        plan: AVFoundationExportPlan
    ) throws -> AVAssetExportSession {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: plan.presetName) else {
            throw AVFoundationMediaExporterError.unsupportedPreset(plan.presetName)
        }

        guard exportSession.supportedFileTypes.contains(plan.outputFileType) else {
            throw AVFoundationMediaExporterError.unsupportedOutputFileType(plan.outputFileType.rawValue)
        }

        return exportSession
    }

    private func makeVideoComposition(
        sourceVideoTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
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
            throw AVFoundationMediaExporterError.invalidVideoDimensions
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

public enum AVFoundationMediaExporterError: Error, Equatable {
    case missingVideoTrack
    case cannotCreateVideoTrack
    case cannotCreateAudioTrack
    case invalidVideoDimensions
    case unsupportedPreset(String)
    case unsupportedOutputFileType(String)
}
