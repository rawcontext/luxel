import AVFoundation
import CoreMedia
import Foundation

extension AVFoundationMediaExporter {
    func makeVideoExportComposition(
        input: MediaExportInput,
        plan: AVFoundationExportPlan,
        asset: AVURLAsset,
        sourceVideoTrack: AVAssetTrack
    ) async throws -> AVFoundationVideoExportComposition {
        let request = input.request
        let composition = AVMutableComposition()
        let sourceSegments = try request.timelineMapper.sourceSegments
        let sourceTimeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(
                seconds: try request.timelineMapper.unscaledOutputDuration,
                preferredTimescale: 60_000
            )
        )
        let outputDuration = CMTime(seconds: request.outputDuration, preferredTimescale: 60_000)
        let videoTrack = try addVideoTrack(
            to: composition,
            from: sourceVideoTrack,
            sourceSegments: sourceSegments
        )
        let audioTracks: [AVMutableCompositionTrack]
        if !plan.shouldMute, let preparedAudio = input.preparedAudio {
            audioTracks = try await addPreparedAudioTracks(
                to: composition,
                preparedAudio: preparedAudio
            )
        } else if !plan.shouldMute {
            audioTracks = try await addAudioTracks(
                to: composition,
                from: asset,
                sourceSegments: sourceSegments
            )
        } else {
            audioTracks = []
        }
        if request.speed != .normal {
            composition.scaleTimeRange(sourceTimeRange, toDuration: outputDuration)
        }
        return AVFoundationVideoExportComposition(
            composition: composition,
            videoTrack: videoTrack,
            audioTracks: audioTracks,
            timeRange: CMTimeRange(start: .zero, duration: outputDuration)
        )
    }

    func exportAudioOnly(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        let plan = try planFactory.makePlan(for: request, outputFileURL: outputFileURL)
        let asset = AVURLAsset(url: plan.inputFileURL)
        let composition = AVMutableComposition()
        let sourceSegments = try request.timelineMapper.sourceSegments
        let sourceCompositionTimeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(
                seconds: try request.timelineMapper.unscaledOutputDuration,
                preferredTimescale: 60_000
            )
        )
        let outputDuration = CMTime(seconds: request.outputDuration, preferredTimescale: 60_000)
        let outputCompositionTimeRange = CMTimeRange(start: .zero, duration: outputDuration)
        let compositionAudioTracks: [AVMutableCompositionTrack]

        if !plan.shouldMute, let preparedAudio = input.preparedAudio {
            compositionAudioTracks = try await addPreparedAudioTracks(
                to: composition,
                preparedAudio: preparedAudio
            )
        } else if !plan.shouldMute {
            compositionAudioTracks = try await addAudioTracks(
                to: composition,
                from: asset,
                sourceSegments: sourceSegments
            )
        } else {
            compositionAudioTracks = []
        }

        guard !compositionAudioTracks.isEmpty else {
            throw AVFoundationMediaExporterError.missingAudioTrack
        }

        if request.speed != .normal {
            composition.scaleTimeRange(sourceCompositionTimeRange, toDuration: outputDuration)
        }

        let audioMix = try await makeAudioMix(
            for: compositionAudioTracks,
            request: request,
            appliesGain: input.preparedAudio == nil
        )
        try await runAudioOnlyExport(
            context: AVFoundationAudioExportContext(
                composition: composition,
                audioTracks: compositionAudioTracks,
                timeRange: outputCompositionTimeRange,
                outputFileURL: plan.outputFileURL,
                format: request.format,
                audioMix: audioMix
            ),
            progress: progress
        )

        return ExportedMedia(
            fileURL: plan.outputFileURL,
            format: request.format,
            pixelSize: plan.outputPixelSize,
            shouldMute: plan.shouldMute
        )
    }

    func runExportSession(
        _ exportSession: AVAssetExportSession,
        plan: AVFoundationExportPlan,
        progress: MediaExportProgressHandler?
    ) async throws {
        guard let outputFileType = plan.outputFileType else {
            throw AVFoundationMediaExporterError.unsupportedOutputFileType(
                requestedOutputFileTypeName(plan: plan))
        }

        try? FileManager.default.removeItem(at: plan.outputFileURL)
        let progressTask = Self.startProgressPolling(exportSession, progress: progress)

        do {
            try await exportSession.export(to: plan.outputFileURL, as: outputFileType)
            await Self.stopProgressPolling(progressTask)
            await progress?(1)
        } catch {
            await Self.stopProgressPolling(progressTask)
            try? FileManager.default.removeItem(at: plan.outputFileURL)
            throw error
        }
    }

    static func startProgressPolling(
        _ exportSession: AVAssetExportSession,
        progress: MediaExportProgressHandler?
    ) -> Task<Void, Never>? {
        guard let progress else {
            return nil
        }

        let progressSource = AVAssetExportSessionProgressSource(exportSession)
        return Task {
            await progress(0)

            while !Task.isCancelled {
                await progress(progressSource.progress)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    static func stopProgressPolling(_ task: Task<Void, Never>?) async {
        guard let task else {
            return
        }

        task.cancel()
        await task.value
    }

    func firstVideoTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AVFoundationMediaExporterError.missingVideoTrack
        }

        return videoTrack
    }

    func addVideoTrack(
        to composition: AVMutableComposition,
        from sourceVideoTrack: AVAssetTrack,
        sourceSegments: [SourceMediaSegment]
    ) throws -> AVMutableCompositionTrack {
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AVFoundationMediaExporterError.cannotCreateVideoTrack
        }

        for segment in sourceSegments {
            try videoTrack.insertTimeRange(
                segment.sourceRange.cmTimeRange,
                of: sourceVideoTrack,
                at: CMTime(seconds: segment.outputStart, preferredTimescale: 60_000)
            )
        }
        return videoTrack
    }

    func addAudioTracks(
        to composition: AVMutableComposition,
        from asset: AVURLAsset,
        sourceSegments: [SourceMediaSegment]
    ) async throws -> [AVMutableCompositionTrack] {
        var audioTracks: [AVMutableCompositionTrack] = []

        for sourceAudioTrack in try await asset.loadTracks(withMediaType: .audio) {
            guard
                let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
                throw AVFoundationMediaExporterError.cannotCreateAudioTrack
            }

            for segment in sourceSegments {
                try audioTrack.insertTimeRange(
                    segment.sourceRange.cmTimeRange,
                    of: sourceAudioTrack,
                    at: CMTime(seconds: segment.outputStart, preferredTimescale: 60_000)
                )
            }
            audioTracks.append(audioTrack)
        }

        return audioTracks
    }

    func addPreparedAudioTracks(
        to composition: AVMutableComposition,
        preparedAudio: PreparedAudioAsset
    ) async throws -> [AVMutableCompositionTrack] {
        let asset = AVURLAsset(url: preparedAudio.fileURL)
        return try await addAudioTracks(
            to: composition,
            from: asset,
            sourceSegments: [
                SourceMediaSegment(
                    sourceRange: try TimeRange(
                        start: 0,
                        end: preparedAudio.duration
                    ),
                    outputStart: 0
                )
            ]
        )
    }

    func makeAudioMix(
        for audioTracks: [AVMutableCompositionTrack],
        request: ExportRequest,
        appliesGain: Bool
    ) async throws -> AVAudioMix? {
        guard !audioTracks.isEmpty else {
            return nil
        }

        let systemGain: Double
        if appliesGain {
            let sourceAudioTracks: [AudioTrackKind] = [.system]
            let mixPlan =
                request.audioMix
                ?? AudioMixPlan(
                    tracks: sourceAudioTracks.map { AudioTrackMix(kind: $0) }
                )
            systemGain = try await resolvedSystemGain(
                for: mixPlan,
                request: request,
                sourceAudioTracks: sourceAudioTracks
            )
        } else {
            systemGain = 1
        }
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

    func resolvedSystemGain(
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

        let measuredPeaks = try await AVAssetReaderAudioPeakAnalyzer().measurePeaks(
            AudioPeakAnalysisRequest(
                inputFileURL: request.inputFileURL,
                timeRange: request.timeRange,
                editPlan: request.editPlan,
                audioTracks: audibleTracks
            ))
        return mixPlan.resolvedGains(measuredPeaks: measuredPeaks)[.system]
            ?? mixPlan.mix(for: .system).gain
    }

    func makeExportSession(
        for composition: AVMutableComposition,
        plan: AVFoundationExportPlan
    ) throws -> AVAssetExportSession {
        guard let outputFileType = plan.outputFileType else {
            throw AVFoundationMediaExporterError.unsupportedOutputFileType(
                requestedOutputFileTypeName(plan: plan))
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: plan.presetName)
        else {
            throw AVFoundationMediaExporterError.unsupportedPreset(plan.presetName)
        }

        guard exportSession.supportedFileTypes.contains(outputFileType) else {
            throw AVFoundationMediaExporterError.unsupportedOutputFileType(outputFileType.rawValue)
        }

        return exportSession
    }

    func requestedOutputFileTypeName(plan: AVFoundationExportPlan) -> String {
        plan.outputFileURL.pathExtension
    }
}

private extension TimeRange {
    var cmTimeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 60_000),
            duration: CMTime(seconds: duration, preferredTimescale: 60_000)
        )
    }
}
