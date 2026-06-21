import CWebMCodecShims
import Foundation
import LuxelCore

public actor VPXVideoEncoder: CodecVideoEncoder {
    private var handle = VPXEncoderHandle()
    private var frameRate: Int = 0
    private var nextPresentationTimeUnits: Int64 = 0

    public init() {}

    public func prepare(_ configuration: CodecVideoEncoderConfiguration) async throws {
        handle = VPXEncoderHandle()

        frameRate = configuration.frameRate.framesPerSecond
        nextPresentationTimeUnits = 0

        let settings = VPXQualitySettings(quality: configuration.quality)
        var createdEncoder: OpaquePointer?
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = LuxelVPXEncoderCreate(
            Int32(configuration.pixelSize.width),
            Int32(configuration.pixelSize.height),
            Int32(configuration.frameRate.framesPerSecond),
            settings.cqLevel,
            settings.cpuUsed,
            1,
            UInt32(min(ProcessInfo.processInfo.activeProcessorCount, 8)),
            UInt32(max(configuration.frameRate.framesPerSecond * 5, 150)),
            &createdEncoder,
            &errorBuffer,
            errorBuffer.count
        )

        guard status == 0, let createdEncoder else {
            throw WebMCodecError.encoderFailure(.codecErrorMessage(from: errorBuffer))
        }

        handle.encoder = createdEncoder
    }

    public func encode(frame: CodecVideoFrame) async throws -> [EncodedPacket] {
        guard let encoder = handle.encoder else {
            throw WebMCodecError.invalidConfiguration("VP9 encoder was used before prepare.")
        }

        let presentationTimeUnits = Int64((frame.presentationTime * Double(frameRate)).rounded())
        let durationUnits = max(1, UInt32((frame.duration * Double(frameRate)).rounded()))
        nextPresentationTimeUnits = max(
            nextPresentationTimeUnits, presentationTimeUnits + Int64(durationUnits))

        var packetList = LuxelCodecPacketList()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = try frame.frame.yPlane.withUnsafeBytes { yBuffer in
            try frame.frame.uPlane.withUnsafeBytes { uBuffer in
                try frame.frame.vPlane.withUnsafeBytes { vBuffer in
                    guard let yAddress = yBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let uAddress = uBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let vAddress = vBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    else {
                        throw WebMCodecError.invalidConfiguration("I420 frame planes were empty.")
                    }

                    return LuxelVPXEncoderEncodeFrame(
                        encoder,
                        yAddress,
                        frame.frame.yPlane.count,
                        uAddress,
                        frame.frame.uPlane.count,
                        vAddress,
                        frame.frame.vPlane.count,
                        presentationTimeUnits,
                        durationUnits,
                        &packetList,
                        &errorBuffer,
                        errorBuffer.count
                    )
                }
            }
        }
        defer {
            LuxelCodecPacketListDestroy(&packetList)
        }

        guard status == 0 else {
            throw WebMCodecError.encoderFailure(.codecErrorMessage(from: errorBuffer))
        }

        return try packets(from: packetList)
    }

    public func finish() async throws -> [EncodedPacket] {
        guard let encoder = handle.encoder else {
            return []
        }

        var packetList = LuxelCodecPacketList()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = LuxelVPXEncoderFinish(
            encoder,
            nextPresentationTimeUnits,
            &packetList,
            &errorBuffer,
            errorBuffer.count
        )
        defer {
            LuxelCodecPacketListDestroy(&packetList)
        }

        guard status == 0 else {
            throw WebMCodecError.encoderFailure(.codecErrorMessage(from: errorBuffer))
        }

        return try packets(from: packetList)
    }

    private func packets(from packetList: LuxelCodecPacketList) throws -> [EncodedPacket] {
        guard let packets = packetList.packets else {
            return []
        }

        return try (0..<packetList.count).map { index in
            let packet = packets[index]
            let data = Data(bytes: packet.data, count: packet.size)
            return try EncodedPacket(
                data: data,
                presentationTime: Double(packet.presentation_time_units) / Double(frameRate),
                duration: Double(packet.duration_units) / Double(frameRate),
                isKeyFrame: packet.is_key_frame != 0
            )
        }
    }
}

private final class VPXEncoderHandle: @unchecked Sendable {
    var encoder: OpaquePointer?

    deinit {
        if let encoder {
            LuxelVPXEncoderDestroy(encoder)
        }
    }
}

private struct VPXQualitySettings {
    let cqLevel: UInt32
    let cpuUsed: Int32

    init(quality: ExportQuality) {
        switch quality {
        case .compact:
            cqLevel = 40
            cpuUsed = 6
        case .balanced, .lossless:
            cqLevel = 33
            cpuUsed = 4
        case .high:
            cqLevel = 16
            cpuUsed = 2
        }
    }
}
