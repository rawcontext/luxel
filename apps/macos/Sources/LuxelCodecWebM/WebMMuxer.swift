import Foundation
import LuxelCore

public actor WebMMuxer: CodecContainerMuxer {
    private let fileSystem: FileManager
    private var writer: WebMStreamingWriter?
    private var tracks: Set<CodecTrack> = []

    public init(fileSystem: FileManager = .default) {
        self.fileSystem = fileSystem
    }

    public func begin(_ configuration: CodecMuxerConfiguration) async throws {
        guard configuration.format == .webm else {
            throw WebMCodecError.unsupportedFormat(configuration.format)
        }
        guard configuration.tracks.contains(.video) else {
            throw WebMCodecError.muxerFailure("WebM export requires a video track.")
        }
        guard let pixelSize = configuration.pixelSize else {
            throw WebMCodecError.muxerFailure("WebM muxer requires output pixel size metadata.")
        }

        tracks = Set(configuration.tracks)
        let writer = WebMStreamingWriter(
            outputFileURL: configuration.outputFileURL,
            pixelSize: pixelSize,
            hasAudio: tracks.contains(.audio),
            fileSystem: fileSystem
        )
        try writer.begin()
        self.writer = writer
    }

    public func write(_ packet: EncodedPacket, to track: CodecTrack) async throws {
        guard let writer else {
            throw WebMCodecError.muxerFailure("WebM muxer was used before begin.")
        }
        guard tracks.contains(track) else {
            throw WebMCodecError.muxerFailure(
                "WebM muxer received an undeclared \(track.rawValue) packet.")
        }

        try writer.append(WebMPacket(track: track, packet: packet))
    }

    public func finalize() async throws {
        guard let writer else {
            throw WebMCodecError.muxerFailure("WebM muxer was finalized before begin.")
        }

        try writer.finalize()
        reset()
    }

    public func cancel() async {
        writer?.cancel()
        reset()
    }

    private func reset() {
        writer = nil
        tracks.removeAll(keepingCapacity: true)
    }
}

struct WebMPacket {
    let track: CodecTrack
    let packet: EncodedPacket

    var trackNumber: UInt64 {
        switch track {
        case .video:
            1
        case .audio:
            2
        }
    }
}
