import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

extension AVAssetReaderCodecMediaSource {
    func makeVideoOutput(
        sourceVideoTrack: AVAssetTrack,
        compositionVideoTrack: AVCompositionTrack,
        timeRange: CMTimeRange,
        outputPixelSize: PixelSize,
        request: ExportRequest
    ) async throws -> AVAssetReaderVideoCompositionOutput {
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [compositionVideoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                    value: kCVPixelFormatType_32BGRA
                )
            ]
        )
        output.videoComposition = try await videoCompositionFactory.makeVideoComposition(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: compositionVideoTrack,
            timeRange: timeRange,
            outputPixelSize: outputPixelSize,
            frameRate: request.frameRate,
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            zoomBlocks: ZoomExportTimeMapper(
                trimRange: request.timeRange,
                speed: request.speed
            ).map(request.zoomBlocks)
        )
        return output
    }

    func startVideoReading(
        composition: AVMutableComposition,
        output: AVAssetReaderVideoCompositionOutput,
        frameRate: FrameRate
    ) throws {
        let reader = try AVAssetReader(asset: composition)
        guard reader.canAdd(output) else {
            throw AVAssetReaderVideoCodecMediaSourceError.cannotAddVideoOutput
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AVAssetReaderVideoCodecMediaSourceError.readerStartFailed(
                reader.errorDescription
            )
        }
        videoReader = reader
        videoOutput = output
        fallbackFrameDuration = 1 / Double(frameRate.framesPerSecond)
    }

    func firstVideoTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AVAssetReaderVideoCodecMediaSourceError.missingVideoTrack
        }

        return videoTrack
    }

    func addVideoTrack(
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
            throw AVAssetReaderVideoCodecMediaSourceError.cannotCreateVideoTrack
        }

        try videoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: .zero)
        return videoTrack
    }

    func prepareAudioReader(
        sourceAudioTracks: [AVAssetTrack],
        timing: CodecAudioTiming,
        preparedAudio: PreparedAudioAsset?
    ) async throws {
        let composition = AVMutableComposition()
        let source = try await audioSource(
            preparedAudio: preparedAudio,
            sourceAudioTracks: sourceAudioTracks,
            sourceTimeRange: timing.sourceTimeRange
        )

        let compositionAudioTracks = try source.tracks.map { sourceAudioTrack in
            try addAudioTrack(
                to: composition,
                from: sourceAudioTrack,
                sourceTimeRange: source.timeRange
            )
        }
        withExtendedLifetime(source.retainedAsset) {}

        if timing.speed != .normal {
            composition.scaleTimeRange(
                timing.sourceCompositionTimeRange,
                toDuration: timing.outputDuration
            )
        }

        let audioReader = try AVAssetReader(asset: composition)
        let audioOutput = AVAssetReaderAudioMixOutput(
            audioTracks: compositionAudioTracks,
            audioSettings: audioOutputSettings()
        )
        if timing.speed != .normal {
            audioOutput.audioMix = makeAudioMix(for: compositionAudioTracks)
        }

        guard audioReader.canAdd(audioOutput) else {
            throw AVAssetReaderCodecMediaSourceError.cannotAddAudioOutput
        }

        audioReader.add(audioOutput)

        guard audioReader.startReading() else {
            throw AVAssetReaderCodecMediaSourceError.readerStartFailed(audioReader.errorDescription)
        }

        self.audioReader = audioReader
        self.audioOutput = audioOutput
    }

    func audioSource(
        preparedAudio: PreparedAudioAsset?,
        sourceAudioTracks: [AVAssetTrack],
        sourceTimeRange: CMTimeRange
    ) async throws -> CodecAudioSource {
        guard let preparedAudio else {
            return CodecAudioSource(
                tracks: sourceAudioTracks,
                timeRange: sourceTimeRange,
                retainedAsset: nil
            )
        }
        let asset = AVURLAsset(url: preparedAudio.fileURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = tracks.first else {
            throw AVAssetReaderCodecMediaSourceError.readFailed(
                "Prepared audio has no audio track."
            )
        }
        let availableTimeRange = try await sourceTrack.load(.timeRange)
        let requestedDuration = CMTime(
            seconds: preparedAudio.duration,
            preferredTimescale: 60_000
        )
        return CodecAudioSource(
            tracks: tracks,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTimeMinimum(availableTimeRange.duration, requestedDuration)
            ),
            retainedAsset: asset
        )
    }

    func addAudioTrack(
        to composition: AVMutableComposition,
        from sourceAudioTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange
    ) throws -> AVMutableCompositionTrack {
        guard
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AVAssetReaderCodecMediaSourceError.cannotCreateAudioTrack
        }

        do {
            try audioTrack.insertTimeRange(sourceTimeRange, of: sourceAudioTrack, at: .zero)
        } catch {
            throw AVAssetReaderCodecMediaSourceError.readFailed(
                "Could not compose audio: \(error.localizedDescription)"
            )
        }
        return audioTrack
    }

    func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: audioChannelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    func makeAudioMix(for audioTracks: [AVCompositionTrack]) -> AVAudioMix {
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { audioTrack in
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            parameters.audioTimePitchAlgorithm = .timeDomain
            return parameters
        }
        return audioMix
    }
}
