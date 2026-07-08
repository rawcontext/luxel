@preconcurrency import AVFoundation
import AudioToolbox
@preconcurrency import CoreMedia
import Foundation
import LuxelCore

struct AV1MP4AudioInputSetup {
    let input: AVAssetWriterInput
    let formatDescription: CMAudioFormatDescription
    let sampleRate: Int
    let channelCount: Int
}

struct AV1MP4SampleBufferFactory {
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
