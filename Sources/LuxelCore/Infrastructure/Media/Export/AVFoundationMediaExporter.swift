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
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            zoomBlocks: ZoomExportTimeMapper(
                trimRange: request.timeRange,
                speed: request.speed
            ).map(request.zoomBlocks)
        )
        exportSession.timeRange = outputCompositionTimeRange
        exportSession.audioMix = try await makeAudioMix(
            for: compositionAudioTracks,
            request: request
        )
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

    private func makeAudioMix(
        for audioTracks: [AVMutableCompositionTrack],
        request: ExportRequest
    ) async throws -> AVAudioMix? {
        guard !audioTracks.isEmpty else {
            return nil
        }

        let sourceAudioTracks: [AudioTrackKind] = [.system]
        let mixPlan = request.audioMix ?? AudioMixPlan(
            tracks: sourceAudioTracks.map { AudioTrackMix(kind: $0) }
        )
        let systemGain = try await resolvedSystemGain(
            for: mixPlan,
            request: request,
            sourceAudioTracks: sourceAudioTracks
        )
        guard request.speed != .normal || systemGain != 1 else {
            return nil
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { audioTrack in
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            parameters.audioTimePitchAlgorithm = .timeDomain
            parameters.setVolume(Float(systemGain), at: .zero)
            return parameters
        }
        return audioMix
    }

    private func resolvedSystemGain(
        for mixPlan: AudioMixPlan,
        request: ExportRequest,
        sourceAudioTracks: [AudioTrackKind]
    ) async throws -> Double {
        guard mixPlan.normalizePeak else {
            return mixPlan.mix(for: .system).gain
        }

        let sourceAudioTracks = Set(sourceAudioTracks)
        let audibleTracks = mixPlan.tracks.compactMap { track -> AudioTrackKind? in
            guard track.gain > 0, sourceAudioTracks.contains(track.kind) else {
                return nil
            }

            return track.kind
        }
        guard !audibleTracks.isEmpty else {
            return mixPlan.mix(for: .system).gain
        }

        let measuredPeaks = try await AVAssetReaderAudioPeakAnalyzer().measurePeaks(AudioPeakAnalysisRequest(
            inputFileURL: request.inputFileURL,
            timeRange: request.timeRange,
            audioTracks: audibleTracks
        ))
        return mixPlan.resolvedGains(measuredPeaks: measuredPeaks)[.system]
            ?? mixPlan.mix(for: .system).gain
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
