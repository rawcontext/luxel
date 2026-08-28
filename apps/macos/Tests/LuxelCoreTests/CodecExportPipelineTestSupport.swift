import Foundation
import LuxelCore

extension CodecAudioChunk {
    init(dataString: String, presentationTime: TimeInterval, duration: TimeInterval)
        throws {
        try self.init(
            pcmData: Data(dataString.utf8),
            presentationTime: presentationTime,
            duration: duration
        )
    }
}

extension EncodedPacket {
    init(
        dataString: String,
        presentationTime: TimeInterval,
        duration: TimeInterval,
        isKeyFrame: Bool
    ) throws {
        try self.init(
            data: Data(dataString.utf8),
            presentationTime: presentationTime,
            duration: duration,
            isKeyFrame: isKeyFrame
        )
    }
}

extension TimeInterval {
    var shortText: String {
        let rounded = (self * 1_000).rounded() / 1_000
        return String(format: "%.3g", rounded)
    }
}

actor StubContainerMuxer: CodecContainerMuxer {
    private let events: PipelineEventLog

    init(events: PipelineEventLog) {
        self.events = events
    }

    func begin(_ configuration: CodecMuxerConfiguration) async throws {
        let tracks = configuration.tracks.map(\.rawValue).joined(separator: ",")
        await events.append(
            "muxer.begin:\(configuration.format.rawValue):\(tracks)"
        )
    }

    func write(_ packet: EncodedPacket, to track: CodecTrack) async throws {
        let packetText = String(bytes: packet.data, encoding: .utf8) ?? ""
        await events.append("muxer.write:\(track.rawValue):\(packetText)")
    }

    func finalize() async throws {
        await events.append("muxer.finalize")
    }

    func cancel() async {
        await events.append("muxer.cancel")
    }
}
