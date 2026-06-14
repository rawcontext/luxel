import Foundation

public protocol CodecMediaSource: Sendable {
    func prepare(_ request: ExportRequest) async throws -> CodecMediaSourceDescription
    func nextVideoFrame() async throws -> CodecVideoFrame?
    func nextAudioChunk() async throws -> CodecAudioChunk?
}

public protocol CodecVideoEncoder: Sendable {
    func prepare(_ configuration: CodecVideoEncoderConfiguration) async throws
    func encode(frame: CodecVideoFrame) async throws -> [EncodedPacket]
    func finish() async throws -> [EncodedPacket]
}

public protocol CodecAudioEncoder: Sendable {
    func prepare(_ configuration: CodecAudioEncoderConfiguration) async throws
    func encode(chunk: CodecAudioChunk) async throws -> [EncodedPacket]
    func finish() async throws -> [EncodedPacket]
}

public protocol CodecContainerMuxer: Sendable {
    func begin(_ configuration: CodecMuxerConfiguration) async throws
    func write(_ packet: EncodedPacket, to track: CodecTrack) async throws
    func finalize() async throws
    func cancel() async
}
