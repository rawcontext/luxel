@preconcurrency import AVFoundation
import AudioToolbox
@preconcurrency import CoreMedia
import Foundation
import LuxelCore

public actor AV1MP4Muxer: CodecContainerMuxer {
    private let fileSystem: FileManager
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sampleBufferFactory: AV1MP4SampleBufferFactory?
    private var tracks: Set<CodecTrack> = []
    private var outputFileURL: URL?

    public init(fileSystem: FileManager = .default) {
        self.fileSystem = fileSystem
    }

    public func begin(_ configuration: CodecMuxerConfiguration) async throws {
        guard configuration.format == .av1 else {
            throw AV1CodecError.unsupportedFormat(configuration.format)
        }
        guard configuration.tracks.contains(.video) else {
            throw AV1CodecError.muxerFailure("AV1 export requires a video track.")
        }
        guard let pixelSize = configuration.pixelSize else {
            throw AV1CodecError.muxerFailure("AV1 muxer requires output pixel size metadata.")
        }

        let writer = try makeWriter(outputFileURL: configuration.outputFileURL)
        let videoDescription = try AV1MP4SampleBufferFactory.makeVideoFormatDescription(
            pixelSize: pixelSize)
        let videoInput = try addVideoInput(to: writer, formatDescription: videoDescription)
        let audioSetup = try addAudioInputIfNeeded(to: writer, configuration: configuration)

        guard writer.startWriting() else {
            throw AV1CodecError.muxerFailure(writer.errorDescription)
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.videoInput = videoInput
        audioInput = audioSetup?.input
        sampleBufferFactory = AV1MP4SampleBufferFactory(
            videoFormatDescription: videoDescription,
            audioFormatDescription: audioSetup?.formatDescription,
            audioSampleRate: audioSetup?.sampleRate ?? 0,
            audioChannelCount: audioSetup?.channelCount ?? 0
        )
        tracks = Set(configuration.tracks)
        outputFileURL = configuration.outputFileURL
    }

    public func write(_ packet: EncodedPacket, to track: CodecTrack) async throws {
        guard let writer, let sampleBufferFactory else {
            throw AV1CodecError.muxerFailure("AV1 muxer was used before begin.")
        }
        guard tracks.contains(track) else {
            throw AV1CodecError.muxerFailure(
                "AV1 muxer received an undeclared \(track.rawValue) packet.")
        }

        switch track {
        case .video:
            guard let videoInput else {
                throw AV1CodecError.muxerFailure("AV1 video writer input was not configured.")
            }
            try await append(
                try sampleBufferFactory.makeVideoSampleBuffer(packet),
                to: videoInput,
                writer: writer
            )
        case .audio:
            guard let audioInput else {
                throw AV1CodecError.muxerFailure("AV1 audio writer input was not configured.")
            }
            try await append(
                try sampleBufferFactory.makeAudioSampleBuffer(packet),
                to: audioInput,
                writer: writer
            )
        }
    }

    public func finalize() async throws {
        guard let writer else {
            throw AV1CodecError.muxerFailure("AV1 muxer was finalized before begin.")
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        defer {
            reset()
        }

        await writer.finishWriting()
        switch writer.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        case .failed, .unknown, .writing:
            throw AV1CodecError.muxerFailure(writer.errorDescription)
        @unknown default:
            throw AV1CodecError.muxerFailure(String(describing: writer.status))
        }
    }

    public func cancel() async {
        writer?.cancelWriting()
        if let outputFileURL {
            try? fileSystem.removeItem(at: outputFileURL)
        }
        reset()
    }

    private func append(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput,
        writer: AVAssetWriter
    ) async throws {
        while !input.isReadyForMoreMediaData {
            try writer.throwIfFailed()
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(2))
        }

        guard input.append(sampleBuffer) else {
            throw AV1CodecError.muxerFailure(writer.errorDescription)
        }
    }

    private func makeWriter(outputFileURL: URL) throws -> AVAssetWriter {
        try fileSystem.createDirectory(
            at: outputFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileSystem.fileExists(atPath: outputFileURL.path) {
            try fileSystem.removeItem(at: outputFileURL)
        }

        let writer = try AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        return writer
    }

    private func addVideoInput(
        to writer: AVAssetWriter,
        formatDescription: CMVideoFormatDescription
    ) throws -> AVAssetWriterInput {
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw AV1CodecError.muxerFailure("Could not add AV1 video writer input.")
        }
        writer.add(input)
        return input
    }

    private func addAudioInputIfNeeded(
        to writer: AVAssetWriter,
        configuration: CodecMuxerConfiguration
    ) throws -> AV1MP4AudioInputSetup? {
        guard configuration.tracks.contains(.audio) else {
            return nil
        }
        guard let sampleRate = configuration.audioSampleRate,
            let channelCount = configuration.audioChannelCount
        else {
            throw AV1CodecError.muxerFailure("AV1 muxer requires audio stream metadata.")
        }

        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: AV1AACBitrate.balanced
            ]
        )
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw AV1CodecError.muxerFailure("Could not add AAC audio writer input.")
        }
        writer.add(input)

        return try AV1MP4AudioInputSetup(
            input: input,
            formatDescription: AV1MP4SampleBufferFactory.makeAudioFormatDescription(
                sampleRate: sampleRate,
                channelCount: channelCount
            ),
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        sampleBufferFactory = nil
        tracks.removeAll(keepingCapacity: true)
        outputFileURL = nil
    }
}

private enum AV1AACBitrate {
    static let balanced = 128_000
}

extension AVAssetWriter {
    fileprivate var errorDescription: String {
        error.map(String.init(describing:)) ?? "Unknown AVAssetWriter error"
    }

    fileprivate func throwIfFailed() throws {
        switch status {
        case .failed:
            throw AV1CodecError.muxerFailure(errorDescription)
        case .cancelled:
            throw CancellationError()
        case .unknown, .writing, .completed:
            return
        @unknown default:
            throw AV1CodecError.muxerFailure(String(describing: status))
        }
    }
}
