import CWebMCodecShims
import Foundation
import LuxelCore

public actor OpusAudioEncoder: CodecAudioEncoder {
    private static let requiredSampleRate = 48_000
    private static let requiredChannelCount = 2
    private static let frameSizePerChannel = 960

    private var handle = OpusEncoderHandle()
    private var pendingPCM = Data()
    private var nextPresentationTime: TimeInterval?

    public init() {}

    public func prepare(_ configuration: CodecAudioEncoderConfiguration) async throws {
        guard configuration.sampleRate == Self.requiredSampleRate,
              configuration.channelCount == Self.requiredChannelCount
        else {
            throw WebMCodecError.invalidConfiguration(
                "Opus expects 48 kHz stereo PCM from the codec media source.")
        }

        handle = OpusEncoderHandle()

        pendingPCM.removeAll(keepingCapacity: true)
        nextPresentationTime = nil

        var createdEncoder: OpaquePointer?
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = LuxelOpusEncoderCreate(
            Int32(configuration.sampleRate),
            Int32(configuration.channelCount),
            Int32(Self.bitrate(for: configuration.quality)),
            &createdEncoder,
            &errorBuffer,
            errorBuffer.count
        )

        guard status == 0, let createdEncoder else {
            throw WebMCodecError.encoderFailure(.codecErrorMessage(from: errorBuffer))
        }

        handle.encoder = createdEncoder
    }

    public func encode(chunk: CodecAudioChunk) async throws -> [EncodedPacket] {
        if nextPresentationTime == nil {
            nextPresentationTime = chunk.presentationTime
        }

        pendingPCM.append(chunk.pcmData)
        return try encodeReadyFrames()
    }

    public func finish() async throws -> [EncodedPacket] {
        guard !pendingPCM.isEmpty else {
            return []
        }

        let frameByteCount = Self.frameByteCount
        if pendingPCM.count < frameByteCount {
            pendingPCM.append(Data(repeating: 0, count: frameByteCount - pendingPCM.count))
        }

        return try encodeReadyFrames()
    }

    private func encodeReadyFrames() throws -> [EncodedPacket] {
        guard let encoder = handle.encoder else {
            throw WebMCodecError.invalidConfiguration("Opus encoder was used before prepare.")
        }

        var encodedPackets: [EncodedPacket] = []
        let frameByteCount = Self.frameByteCount

        while pendingPCM.count >= frameByteCount {
            let frameData = pendingPCM.prefix(frameByteCount)
            pendingPCM.removeFirst(frameByteCount)

            var packetList = LuxelCodecPacketList()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = frameData.withUnsafeBytes { pcmBuffer in
                guard let pcmAddress = pcmBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                    return Int32(-1)
                }

                return LuxelOpusEncoderEncode(
                    encoder,
                    pcmAddress,
                    Int32(Self.frameSizePerChannel),
                    &packetList,
                    &errorBuffer,
                    errorBuffer.count
                )
            }
            defer {
                LuxelCodecPacketListDestroy(&packetList)
            }

            guard status == 0 else {
                throw WebMCodecError.encoderFailure(.codecErrorMessage(from: errorBuffer))
            }

            encodedPackets.append(contentsOf: try packets(from: packetList))
        }

        return encodedPackets
    }

    private func packets(from packetList: LuxelCodecPacketList) throws -> [EncodedPacket] {
        guard let packets = packetList.packets else {
            return []
        }

        return try (0..<packetList.count).map { index in
            let packet = packets[index]
            let presentationTime = nextPresentationTime ?? 0
            let duration = Self.frameDuration
            nextPresentationTime = presentationTime + duration

            return try EncodedPacket(
                data: Data(bytes: packet.data, count: packet.size),
                presentationTime: presentationTime,
                duration: duration,
                isKeyFrame: true
            )
        }
    }

    private static var frameByteCount: Int {
        frameSizePerChannel * requiredChannelCount * MemoryLayout<Int16>.size
    }

    private static var frameDuration: TimeInterval {
        Double(frameSizePerChannel) / Double(requiredSampleRate)
    }

    private static func bitrate(for quality: ExportQuality) -> Int {
        switch quality {
        case .compact:
            96_000
        case .balanced, .lossless:
            128_000
        case .high:
            160_000
        }
    }
}

private final class OpusEncoderHandle: @unchecked Sendable {
    var encoder: OpaquePointer?

    deinit {
        if let encoder {
            LuxelOpusEncoderDestroy(encoder)
        }
    }
}
