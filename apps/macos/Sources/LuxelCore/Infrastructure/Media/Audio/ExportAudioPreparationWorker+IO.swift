import AVFAudio
import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

extension ExportAudioPreparationWorker {
    func makeReader(
        request: ExportRequest
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderAudioMixOutput) {
        let asset = AVURLAsset(url: request.inputFileURL)
        let sourceTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !sourceTracks.isEmpty else {
            throw ExportAudioPreparationError.missingAudioTrack
        }

        let sourceSegments = try request.timelineMapper.sourceSegments
        let composition = AVMutableComposition()
        let tracks = try addAudioTracks(
            sourceTracks,
            sourceSegments: sourceSegments,
            to: composition
        )

        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: ExportAudioPreparationService.sampleRate,
                AVNumberOfChannelsKey: ExportAudioPreparationService.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true
            ]
        )
        guard reader.canAdd(output) else {
            throw ExportAudioPreparationError.sourceReadFailed(
                "AVAssetReader could not add the audio output."
            )
        }
        reader.add(output)
        return (reader, output)
    }

    private func addAudioTracks(
        _ sourceTracks: [AVAssetTrack],
        sourceSegments: [SourceMediaSegment],
        to composition: AVMutableComposition
    ) throws -> [AVMutableCompositionTrack] {
        try sourceTracks.map { sourceTrack in
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportAudioPreparationError.unsupportedAudioLayout
            }
            for segment in sourceSegments {
                try track.insertTimeRange(
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
                    of: sourceTrack,
                    at: CMTime(seconds: segment.outputStart, preferredTimescale: 60_000)
                )
            }
            return track
        }
    }

    func channels(from sampleBuffer: CMSampleBuffer) throws -> [[Float]] {
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: Self.format,
            frameCapacity: frameCount
        ) else {
            throw ExportAudioPreparationError.sourceReadFailed(
                "Could not allocate an audio buffer."
            )
        }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr, let channelData = buffer.floatChannelData else {
            throw ExportAudioPreparationError.sourceReadFailed(
                "Could not copy PCM data (\(status))."
            )
        }

        return (0..<ExportAudioPreparationService.channelCount).map { channel in
            Array(UnsafeBufferPointer(start: channelData[channel], count: Int(frameCount)))
        }
    }

    func applyGain(
        _ gain: Double,
        inputURL: URL,
        outputURL: URL
    ) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let outputFile = try makeAudioFile(forWriting: outputURL)
        let capacity: AVAudioFrameCount = 4_096
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: Self.format,
            frameCapacity: capacity
        ) else {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }

        while inputFile.framePosition < inputFile.length {
            try Task.checkCancellation()
            try inputFile.read(into: buffer, frameCount: capacity)
            guard let channelData = buffer.floatChannelData else {
                throw ExportAudioPreparationError.preparedAudioWriteFailed
            }
            for channel in 0..<ExportAudioPreparationService.channelCount {
                for frame in 0..<Int(buffer.frameLength) {
                    let scaled = Double(channelData[channel][frame]) * gain
                    channelData[channel][frame] = scaled.isFinite
                        ? Float(min(max(scaled, -1), 1))
                        : 0
                }
            }
            try outputFile.write(from: buffer)
        }
    }

    func makeAudioFile(forWriting url: URL) throws -> AVAudioFile {
        try? FileManager.default.removeItem(at: url)
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: ExportAudioPreparationService.sampleRate,
                    AVNumberOfChannelsKey: ExportAudioPreparationService.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }
    }

    func finishReading(_ reader: AVAssetReader) throws {
        switch reader.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw ExportAudioPreparationError.sourceReadFailed(
                reader.error?.localizedDescription ?? "Unknown reader failure"
            )
        case .unknown, .reading:
            throw ExportAudioPreparationError.sourceReadFailed(
                "Audio reading did not complete."
            )
        @unknown default:
            throw ExportAudioPreparationError.sourceReadFailed(
                "Audio reading ended in an unknown state."
            )
        }
    }

    func setActiveReader(_ reader: AVAssetReader?) {
        lock.lock()
        activeReader = reader
        lock.unlock()
    }

    func silence(frameCount: Int) -> [[Float]] {
        (0..<ExportAudioPreparationService.channelCount).map { _ in
            [Float](repeating: 0, count: frameCount)
        }
    }
}
