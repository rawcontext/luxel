import Foundation
import LuxelCore

extension CodecAudioChunk {
    init(dataString: String, presentationTime: TimeInterval, duration: TimeInterval)
        throws
    {
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
