import AVFAudio
import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreMedia
import Foundation

public struct AVFoundationMediaExporter: MediaExporter, Sendable {
    let planFactory: AVFoundationExportPlanFactory
    let videoCompositionFactory: AVFoundationVideoCompositionFactory

    public init(planFactory: AVFoundationExportPlanFactory = AVFoundationExportPlanFactory()) {
        self.init(
            planFactory: planFactory,
            videoCompositionFactory: AVFoundationVideoCompositionFactory()
        )
    }

    init(
        planFactory: AVFoundationExportPlanFactory,
        videoCompositionFactory: AVFoundationVideoCompositionFactory
    ) {
        self.planFactory = planFactory
        self.videoCompositionFactory = videoCompositionFactory
    }

    public func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        if request.format.isAudioOnlyFormat {
            return try await exportAudioOnly(input, to: outputFileURL, progress: progress)
        }

        let plan = try planFactory.makePlan(for: request, outputFileURL: outputFileURL)
        let asset = AVURLAsset(url: plan.inputFileURL)
        let sourceVideoTrack = try await firstVideoTrack(in: asset)
        let prepared = try await makeVideoExportComposition(
            input: input,
            plan: plan,
            asset: asset,
            sourceVideoTrack: sourceVideoTrack
        )
        let exportSession = try makeExportSession(for: prepared.composition, plan: plan)
        exportSession.videoComposition = try await videoCompositionFactory.makeVideoComposition(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: prepared.videoTrack,
            timeRange: prepared.timeRange,
            outputPixelSize: plan.outputPixelSize,
            frameRate: request.frameRate,
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            zoomBlocks: ZoomExportTimeMapper(
                trimRange: request.timeRange,
                speed: request.speed,
                editPlan: request.editPlan
            ).map(request.zoomBlocks)
        )
        exportSession.timeRange = prepared.timeRange
        exportSession.audioMix = try await makeAudioMix(
            for: prepared.audioTracks,
            request: request,
            appliesGain: input.preparedAudio == nil
        )
        exportSession.shouldOptimizeForNetworkUse = true

        try await runExportSession(exportSession, plan: plan, progress: progress)

        return ExportedMedia(
            fileURL: plan.outputFileURL,
            format: request.format,
            pixelSize: plan.outputPixelSize,
            shouldMute: plan.shouldMute
        )
    }
}
