import Foundation

struct VoiceActivitySampleFramer: Sendable {
    static let frameSize = 4_096

    private var remainder: [Float] = []

    var bufferedSampleCount: Int {
        remainder.count
    }

    mutating func append(_ samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else {
            return []
        }

        remainder.append(contentsOf: samples)
        let frameCount = remainder.count / Self.frameSize
        guard frameCount > 0 else {
            return []
        }

        var frames: [[Float]] = []
        frames.reserveCapacity(frameCount)
        for frameIndex in 0..<frameCount {
            let start = frameIndex * Self.frameSize
            let end = start + Self.frameSize
            frames.append(Array(remainder[start..<end]))
        }

        remainder = Array(remainder.dropFirst(frameCount * Self.frameSize))
        return frames
    }

    mutating func reset() {
        remainder.removeAll(keepingCapacity: true)
    }
}
