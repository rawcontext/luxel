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

private struct AV1MP4AudioInputSetup {
    let input: AVAssetWriterInput
    let formatDescription: CMAudioFormatDescription
    let sampleRate: Int
    let channelCount: Int
}

private struct AV1MP4SampleBufferFactory {
    let videoFormatDescription: CMVideoFormatDescription
    let audioFormatDescription: CMAudioFormatDescription?
    let audioSampleRate: Int
    let audioChannelCount: Int

    static func makeVideoFormatDescription(pixelSize: PixelSize) throws -> CMVideoFormatDescription {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_AV1,
            width: Int32(pixelSize.width),
            height: Int32(pixelSize.height),
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw AV1CodecError.muxerFailure("Could not create AV1 format description: \(status).")
        }

        return formatDescription
    }

    static func makeAudioFormatDescription(
        sampleRate: Int,
        channelCount: Int
    ) throws -> CMAudioFormatDescription {
        let bytesPerFrame = UInt32(channelCount * MemoryLayout<Int16>.size)
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw AV1CodecError.muxerFailure("Could not create PCM format description: \(status).")
        }

        return formatDescription
    }

    func makeVideoSampleBuffer(_ packet: EncodedPacket) throws -> CMSampleBuffer {
        let blockBuffer = try makeBlockBuffer(packet.data)
        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: max(packet.duration, 1.0 / 60_000), preferredTimescale: 60_000),
            presentationTimeStamp: CMTime(seconds: packet.presentationTime, preferredTimescale: 60_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = packet.data.count
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: videoFormatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw AV1CodecError.muxerFailure("Could not create AV1 sample buffer: \(status).")
        }
        if !packet.isKeyFrame {
            try markVideoSampleNotSync(sampleBuffer)
        }

        return sampleBuffer
    }

    func makeAudioSampleBuffer(_ packet: EncodedPacket) throws -> CMSampleBuffer {
        guard let audioFormatDescription else {
            throw AV1CodecError.muxerFailure("AV1 audio format description was not configured.")
        }

        let bytesPerFrame = audioChannelCount * MemoryLayout<Int16>.size
        guard bytesPerFrame > 0, packet.data.count.isMultiple(of: bytesPerFrame) else {
            throw AV1CodecError.muxerFailure("PCM audio packet size did not match stream metadata.")
        }

        let blockBuffer = try makeBlockBuffer(packet.data)
        let sampleCount = packet.data.count / bytesPerFrame
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(audioSampleRate)),
            presentationTimeStamp: CMTime(seconds: packet.presentationTime, preferredTimescale: 60_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerFrame
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: audioFormatDescription,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw AV1CodecError.muxerFailure("Could not create PCM sample buffer: \(status).")
        }

        return sampleBuffer
    }

    private func makeBlockBuffer(_ data: Data) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == noErr, let blockBuffer else {
            throw AV1CodecError.muxerFailure("Could not create media block buffer: \(createStatus).")
        }

        let replaceStatus = data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(paramErr)
            }

            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        guard replaceStatus == noErr else {
            throw AV1CodecError.muxerFailure("Could not copy media packet data: \(replaceStatus).")
        }

        return blockBuffer
    }

    private func markVideoSampleNotSync(_ sampleBuffer: CMSampleBuffer) throws {
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: true
            )
        else {
            throw AV1CodecError.muxerFailure("Could not create video sample attachments.")
        }

        let attachments = unsafeBitCast(
            CFArrayGetValueAtIndex(attachmentsArray, 0),
            to: CFMutableDictionary.self
        )
        CFDictionarySetValue(
            attachments,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
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
