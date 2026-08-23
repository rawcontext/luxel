import AVFAudio
import Foundation

final class RollingPCMBuffer {
    private var channels: [[Float]]
    private var startIndex = 0

    init(channelCount: Int) {
        channels = (0..<channelCount).map { _ in [] }
    }

    var frameCount: Int {
        channels[0].count - startIndex
    }

    func append(_ samples: [[Float]]) {
        for channel in channels.indices {
            channels[channel].append(contentsOf: samples[channel])
        }
    }

    func prefix(_ frameCount: Int) -> [[Float]] {
        channels.map { channel in
            Array(channel[startIndex..<(startIndex + frameCount)])
        }
    }

    func consume(_ frameCount: Int) {
        startIndex += min(frameCount, self.frameCount)
        if startIndex >= 65_536 {
            channels = channels.map { Array($0.dropFirst(startIndex)) }
            startIndex = 0
        }
    }
}

final class BoundedPCMWriter {
    private let outputFile: AVAudioFile
    private(set) var peak = 0.0

    init(outputFile: AVAudioFile) {
        self.outputFile = outputFile
    }

    func write(_ channels: [[Float]]) throws {
        guard let frameCount = channels.first?.count, frameCount > 0 else {
            return
        }
        guard channels.allSatisfy({ $0.count == frameCount }),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: ExportAudioPreparationWorker.format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ),
            let channelData = buffer.floatChannelData
        else {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        for channel in channels.indices {
            for frame in 0..<frameCount {
                let sample = channels[channel][frame].isFinite ? channels[channel][frame] : 0
                channelData[channel][frame] = sample
                peak = max(peak, Double(abs(sample)))
            }
        }
        do {
            try outputFile.write(from: buffer)
        } catch {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }
    }
}

struct EmptyAudioPeakAnalyzer: AudioPeakAnalyzer {
    func measurePeaks(
        _ request: AudioPeakAnalysisRequest
    ) async throws -> [AudioTrackKind: Double] {
        [:]
    }
}

public enum ExportAudioPreparationError: Error, Equatable {
    case preparerUnavailable
    case missingAudioTrack
    case unsupportedAudioLayout
    case sourceReadFailed(String)
    case preparedAudioWriteFailed
}

extension ExportAudioPreparationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .preparerUnavailable:
            LuxelLocalization.string(
                "studioVoice.error.unavailable",
                defaultValue: "This export requires local audio preparation, but it is unavailable."
            )
        case .missingAudioTrack, .unsupportedAudioLayout:
            LuxelLocalization.string(
                "studioVoice.error.audioLayout",
                defaultValue: "Studio Voice could not use this recording's audio layout."
            )
        case .sourceReadFailed:
            LuxelLocalization.string(
                "studioVoice.error.sourceRead",
                defaultValue: "Studio Voice could not read the selected audio."
            )
        case .preparedAudioWriteFailed:
            LuxelLocalization.string(
                "studioVoice.error.write",
                defaultValue: "Studio Voice could not create its temporary export audio."
            )
        }
    }
}
