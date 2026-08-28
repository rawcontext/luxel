import AVFoundation
import Accelerate
import CoreMedia
import Foundation

public struct AVAssetReaderAudioPeakAnalyzer: AudioPeakAnalyzer {
    private let sampleRate = 48_000
    private let channelCount = 2

    public init() {}

    public func measurePeaks(_ request: AudioPeakAnalysisRequest) async throws -> [AudioTrackKind:
        Double] {
        guard !request.audioTracks.isEmpty else {
            return [:]
        }

        let peak = try await mixedPeak(for: request)
        return Dictionary(uniqueKeysWithValues: request.audioTracks.map { ($0, peak) })
    }

    private func mixedPeak(for request: AudioPeakAnalysisRequest) async throws -> Double {
        let asset = AVURLAsset(url: request.inputFileURL)
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !sourceAudioTracks.isEmpty else {
            return 0
        }

        let sourceSegments = try EditedTimelineMapper(
            trimRange: request.timeRange,
            editPlan: request.editPlan
        ).sourceSegments
        let composition = AVMutableComposition()
        let compositionAudioTracks = try sourceAudioTracks.map { sourceAudioTrack in
            try addAudioTrack(
                to: composition,
                from: sourceAudioTrack,
                sourceSegments: sourceSegments
            )
        }

        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: compositionAudioTracks,
            audioSettings: audioOutputSettings()
        )

        guard reader.canAdd(output) else {
            throw AVAssetReaderAudioPeakAnalyzerError.cannotAddAudioOutput
        }

        reader.add(output)

        guard reader.startReading() else {
            throw AVAssetReaderAudioPeakAnalyzerError.readerStartFailed(reader.errorDescription)
        }

        var peak = 0.0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            peak = max(peak, try peakValue(in: sampleBuffer))
        }

        switch reader.status {
        case .failed:
            throw AVAssetReaderAudioPeakAnalyzerError.readFailed(reader.errorDescription)
        case .cancelled:
            throw CancellationError()
        case .completed, .reading, .unknown:
            return peak
        @unknown default:
            return peak
        }
    }

    private func addAudioTrack(
        to composition: AVMutableComposition,
        from sourceAudioTrack: AVAssetTrack,
        sourceSegments: [SourceMediaSegment]
    ) throws -> AVMutableCompositionTrack {
        guard
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AVAssetReaderAudioPeakAnalyzerError.cannotCreateAudioTrack
        }

        for segment in sourceSegments {
            try audioTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(
                        seconds: segment.sourceRange.start,
                        preferredTimescale: 60_000
                    ),
                    duration: CMTime(
                        seconds: segment.sourceRange.duration,
                        preferredTimescale: 60_000
                    )
                ),
                of: sourceAudioTrack,
                at: CMTime(seconds: segment.outputStart, preferredTimescale: 60_000)
            )
        }
        return audioTrack
    }

    private func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private func peakValue(in sampleBuffer: CMSampleBuffer) throws -> Double {
        let data = try pcmData(from: sampleBuffer)
        return data.withUnsafeBytes { buffer in
            let samples = buffer.bindMemory(to: Float32.self)
            guard !samples.isEmpty else {
                return 0
            }

            let magnitude = vDSP.maximumMagnitude(samples)
            guard magnitude.isFinite else {
                return samples.reduce(0.0) { peak, sample in
                    guard sample.isFinite else {
                        return peak
                    }

                    return max(peak, Double(abs(sample)))
                }
            }

            return Double(magnitude)
        }
    }

    private func pcmData(from sampleBuffer: CMSampleBuffer) throws -> Data {
        try sampleBuffer.copiedPCMData(
            missingDataError: AVAssetReaderAudioPeakAnalyzerError.missingAudioData,
            copyError: AVAssetReaderAudioPeakAnalyzerError.audioDataCopyFailed
        )
    }
}

public enum AVAssetReaderAudioPeakAnalyzerError: Error, Equatable {
    case cannotCreateAudioTrack
    case cannotAddAudioOutput
    case readerStartFailed(String)
    case readFailed(String)
    case missingAudioData
    case audioDataCopyFailed(OSStatus)
}

extension AVAssetReader {
    var errorDescription: String {
        error.map(String.init(describing:)) ?? "Unknown AVAssetReader error"
    }
}
