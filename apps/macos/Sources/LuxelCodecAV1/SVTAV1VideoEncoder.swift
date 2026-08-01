import CAV1CodecShims
import Foundation
import LuxelCore

public actor SVTAV1VideoEncoder: CodecVideoEncoder {
    private var handle = SVTAV1EncoderHandle()
    private var frameRate: Int = 0

    public init() {}

    public func prepare(_ configuration: CodecVideoEncoderConfiguration) async throws {
        handle = SVTAV1EncoderHandle()

        frameRate = configuration.frameRate.framesPerSecond

        let settings = SVTAV1QualitySettings(quality: configuration.quality)
        var createdEncoder: OpaquePointer?
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = LuxelAV1EncoderCreate(
            Int32(configuration.pixelSize.width),
            Int32(configuration.pixelSize.height),
            Int32(configuration.frameRate.framesPerSecond),
            settings.preset,
            settings.quantizer,
            UInt32(max(configuration.frameRate.framesPerSecond * 5, 150)),
            0,
            &createdEncoder,
            &errorBuffer,
            errorBuffer.count
        )

        guard status == 0, let createdEncoder else {
            throw AV1CodecError.encoderFailure(.av1CodecErrorMessage(from: errorBuffer))
        }

        handle.encoder = createdEncoder
    }

    public func encode(frame: CodecVideoFrame) async throws -> [EncodedPacket] {
        guard let encoder = handle.encoder else {
            throw AV1CodecError.invalidConfiguration("AV1 encoder was used before prepare.")
        }

        let presentationTimeUnits = Int64((frame.presentationTime * Double(frameRate)).rounded())
        let durationUnits = max(1, UInt32((frame.duration * Double(frameRate)).rounded()))

        var packetList = LuxelAV1PacketList()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let planeCounts = (
            y: frame.frame.yPlane.count,
            u: frame.frame.uPlane.count,
            v: frame.frame.vPlane.count
        )
        let status = try frame.withUnsafeI420Planes(
            emptyPlanesError: AV1CodecError.invalidConfiguration("I420 frame planes were empty.")
        ) { yAddress, uAddress, vAddress in
            LuxelAV1EncoderEncodeFrame(
                encoder,
                yAddress,
                planeCounts.y,
                uAddress,
                planeCounts.u,
                vAddress,
                planeCounts.v,
                presentationTimeUnits,
                durationUnits,
                &packetList,
                &errorBuffer,
                errorBuffer.count
            )
        }
        defer {
            LuxelAV1PacketListDestroy(&packetList)
        }

        guard status == 0 else {
            throw AV1CodecError.encoderFailure(.av1CodecErrorMessage(from: errorBuffer))
        }

        return try packets(from: packetList)
    }

    public func finish() async throws -> [EncodedPacket] {
        guard let encoder = handle.encoder else {
            return []
        }

        var packetList = LuxelAV1PacketList()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = LuxelAV1EncoderFinish(
            encoder,
            &packetList,
            &errorBuffer,
            errorBuffer.count
        )
        defer {
            LuxelAV1PacketListDestroy(&packetList)
        }

        guard status == 0 else {
            throw AV1CodecError.encoderFailure(.av1CodecErrorMessage(from: errorBuffer))
        }

        return try packets(from: packetList)
    }

    private func packets(from packetList: LuxelAV1PacketList) throws -> [EncodedPacket] {
        guard let packets = packetList.packets else {
            return []
        }

        return try (0..<packetList.count).map { index in
            let packet = packets[index]
            return try EncodedPacket(
                data: Data(bytes: packet.data, count: packet.size),
                presentationTime: Double(packet.presentation_time_units) / Double(frameRate),
                duration: Double(max(packet.duration_units, 1)) / Double(frameRate),
                isKeyFrame: packet.is_key_frame != 0
            )
        }
    }
}

private final class SVTAV1EncoderHandle: @unchecked Sendable {
    var encoder: OpaquePointer?

    deinit {
        if let encoder {
            LuxelAV1EncoderDestroy(encoder)
        }
    }
}

private struct SVTAV1QualitySettings {
    let preset: Int32
    let quantizer: UInt32

    init(quality: ExportQuality) {
        switch quality {
        case .compact:
            preset = 10
            quantizer = 44
        case .balanced, .lossless:
            preset = 8
            quantizer = 36
        case .high:
            preset = 6
            quantizer = 28
        }
    }
}
