import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

public struct AVFoundationMediaExporter: MediaExporter, Sendable {
    private let planFactory: AVFoundationExportPlanFactory
    private let videoCompositionFactory: AVFoundationVideoCompositionFactory

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

    public func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        let plan = try planFactory.makePlan(for: request, outputFileURL: outputFileURL)
        let asset = AVURLAsset(url: plan.inputFileURL)
        let sourceVideoTrack = try await firstVideoTrack(in: asset)
        let composition = AVMutableComposition()
        let sourceCompositionTimeRange = CMTimeRange(start: .zero, duration: plan.timeRange.duration)
        let outputDuration = CMTime(seconds: request.outputDuration, preferredTimescale: 60_000)
        let outputCompositionTimeRange = CMTimeRange(start: .zero, duration: outputDuration)
        let compositionVideoTrack = try addVideoTrack(
            to: composition,
            from: sourceVideoTrack,
            sourceTimeRange: plan.timeRange
        )
        let compositionAudioTracks: [AVMutableCompositionTrack]

        if !plan.shouldMute {
            compositionAudioTracks = try await addAudioTracks(
                to: composition,
                from: asset,
                sourceTimeRange: plan.timeRange
            )
        } else {
            compositionAudioTracks = []
        }

        if request.speed != .normal {
            composition.scaleTimeRange(sourceCompositionTimeRange, toDuration: outputDuration)
        }

        let exportSession = try makeExportSession(for: composition, plan: plan)
        exportSession.videoComposition = try await videoCompositionFactory.makeVideoComposition(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: compositionVideoTrack,
            timeRange: outputCompositionTimeRange,
            outputPixelSize: plan.outputPixelSize,
            frameRate: request.frameRate,
            shouldCrop: request.shouldCrop
        )
        exportSession.timeRange = outputCompositionTimeRange
        exportSession.audioMix = request.speed == .normal
            ? nil
            : makeAudioMix(for: compositionAudioTracks)
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
    ) async throws -> [AVMutableCompositionTrack] {
        var audioTracks: [AVMutableCompositionTrack] = []

        for sourceAudioTrack in try await asset.loadTracks(withMediaType: .audio) {
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw AVFoundationMediaExporterError.cannotCreateAudioTrack
            }

            try audioTrack.insertTimeRange(sourceTimeRange, of: sourceAudioTrack, at: .zero)
            audioTracks.append(audioTrack)
        }

        return audioTracks
    }

    private func makeAudioMix(for audioTracks: [AVMutableCompositionTrack]) -> AVAudioMix? {
        guard !audioTracks.isEmpty else {
            return nil
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { audioTrack in
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            parameters.audioTimePitchAlgorithm = .timeDomain
            return parameters
        }
        return audioMix
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

}

public enum AVFoundationMediaExporterError: Error, Equatable {
    case missingVideoTrack
    case cannotCreateVideoTrack
    case cannotCreateAudioTrack
    case unsupportedPreset(String)
    case unsupportedOutputFileType(String)
}
