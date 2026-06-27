import AVFAudio
import AVFoundation
import AudioToolbox
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
        try await export(request, to: outputFileURL, progress: nil)
    }

    public func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        if request.format.isAudioOnlyFormat {
            return try await exportAudioOnly(request, to: outputFileURL, progress: progress)
        }

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

        try await runExportSession(exportSession, plan: plan, progress: progress)

        return ExportedMedia(
            fileURL: plan.outputFileURL,
            format: request.format,
            pixelSize: plan.outputPixelSize,
            shouldMute: plan.shouldMute
        )
    }

    private func exportAudioOnly(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let plan = try planFactory.makePlan(for: request, outputFileURL: outputFileURL)
        let asset = AVURLAsset(url: plan.inputFileURL)
        let composition = AVMutableComposition()
        let sourceCompositionTimeRange = CMTimeRange(start: .zero, duration: plan.timeRange.duration)
        let outputDuration = CMTime(seconds: request.outputDuration, preferredTimescale: 60_000)
        let outputCompositionTimeRange = CMTimeRange(start: .zero, duration: outputDuration)
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

        guard !compositionAudioTracks.isEmpty else {
            throw AVFoundationMediaExporterError.missingAudioTrack
        }

        if request.speed != .normal {
            composition.scaleTimeRange(sourceCompositionTimeRange, toDuration: outputDuration)
        }

        let audioMix = try await makeAudioMix(
            for: compositionAudioTracks,
            request: request
        )
        try await runAudioOnlyExport(
            composition: composition,
            audioTracks: compositionAudioTracks,
            timeRange: outputCompositionTimeRange,
            outputFileURL: plan.outputFileURL,
            format: request.format,
            audioMix: audioMix,
            progress: progress
        )

        return ExportedMedia(
            fileURL: plan.outputFileURL,
            format: request.format,
            pixelSize: plan.outputPixelSize,
            shouldMute: plan.shouldMute
        )
    }

    private func runExportSession(
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

    private static func startProgressPolling(
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

    private static func stopProgressPolling(_ task: Task<Void, Never>?) async {
        guard let task else {
            return
        }

        task.cancel()
        await task.value
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
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
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
            guard
                let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
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
        let mixPlan =
            request.audioMix
            ?? AudioMixPlan(
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

        let measuredPeaks = try await AVAssetReaderAudioPeakAnalyzer().measurePeaks(
            AudioPeakAnalysisRequest(
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

    private func requestedOutputFileTypeName(plan: AVFoundationExportPlan) -> String {
        plan.outputFileURL.pathExtension
    }

}

extension AVFoundationMediaExporter {
    fileprivate static let audioProcessingSampleRate = 48_000.0
    fileprivate static let audioProcessingChannelCount: AVAudioChannelCount = 2

    fileprivate static var audioProcessingFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audioProcessingSampleRate,
            channels: audioProcessingChannelCount,
            interleaved: false
        )!
    }

    fileprivate static var audioReaderOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioProcessingSampleRate,
            AVNumberOfChannelsKey: Int(audioProcessingChannelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
    }

    fileprivate func runAudioOnlyExport(
        composition: AVMutableComposition,
        audioTracks: [AVMutableCompositionTrack],
        timeRange: CMTimeRange,
        outputFileURL: URL,
        format: ExportFormat,
        audioMix: AVAudioMix?,
        progress: MediaExportProgressHandler?
    ) async throws {
        try? FileManager.default.removeItem(at: outputFileURL)

        do {
            let reader = try AVAssetReader(asset: composition)
            reader.timeRange = timeRange

            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: Self.audioReaderOutputSettings
            )
            output.audioMix = audioMix

            guard reader.canAdd(output) else {
                throw AVFoundationMediaExporterError.cannotCreateAudioReaderOutput
            }
            reader.add(output)

            let outputFile = try AVAudioFile(
                forWriting: outputFileURL,
                settings: try audioOutputSettings(for: format),
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let processingFormat = Self.audioProcessingFormat
            let totalDuration = max(timeRange.duration.seconds, .leastNonzeroMagnitude)

            guard reader.startReading() else {
                throw AVFoundationMediaExporterError.audioReaderFailed(
                    reader.error?.localizedDescription ?? "Unknown reader failure")
            }

            await progress?(0)

            while reader.status == .reading {
                try Task.checkCancellation()

                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    break
                }

                let buffer = try audioPCMBuffer(from: sampleBuffer, format: processingFormat)
                try outputFile.write(from: buffer)

                let sampleEnd =
                    CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    + CMSampleBufferGetDuration(sampleBuffer)
                if sampleEnd.isNumeric {
                    await progress?(min(max(sampleEnd.seconds / totalDuration, 0), 0.99))
                }
            }

            switch reader.status {
            case .completed:
                await progress?(1)
            case .failed:
                throw AVFoundationMediaExporterError.audioReaderFailed(
                    reader.error?.localizedDescription ?? "Unknown reader failure")
            case .cancelled:
                throw CancellationError()
            case .unknown, .reading:
                throw AVFoundationMediaExporterError.audioReaderFailed(String(describing: reader.status))
            @unknown default:
                throw AVFoundationMediaExporterError.audioReaderFailed(String(describing: reader.status))
            }
        } catch {
            try? FileManager.default.removeItem(at: outputFileURL)
            throw error
        }
    }

    fileprivate func audioOutputSettings(for format: ExportFormat) throws -> [String: Any] {
        switch format {
        case .m4a:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount),
                AVEncoderBitRateKey: 128_000
            ]
        case .alac:
            [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount),
                AVEncoderBitDepthHintKey: 16
            ]
        case .wav, .caf:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .flac:
            [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount)
            ]
        case .mp4, .hevc, .proRes422, .proRes4444, .gif, .webm, .apng, .av1:
            throw AVFoundationExportPlanError.unsupportedFormat(format)
        }
    }

    fileprivate func audioPCMBuffer(
        from sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AVFoundationMediaExporterError.cannotCreateAudioBuffer
        }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw AVFoundationMediaExporterError.cannotCopyPCMData(status)
        }

        return buffer
    }
}

private final class AVAssetExportSessionProgressSource: @unchecked Sendable {
    private let exportSession: AVAssetExportSession

    init(_ exportSession: AVAssetExportSession) {
        self.exportSession = exportSession
    }

    var progress: Double {
        Double(exportSession.progress)
    }
}

public enum AVFoundationMediaExporterError: Error, Equatable {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateVideoTrack
    case cannotCreateAudioTrack
    case unsupportedPreset(String)
    case unsupportedOutputFileType(String)
    case cannotCreateAudioReaderOutput
    case cannotCreateAudioBuffer
    case cannotCopyPCMData(OSStatus)
    case audioReaderFailed(String)
}
