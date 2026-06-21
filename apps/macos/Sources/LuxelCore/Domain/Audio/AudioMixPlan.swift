import Foundation

public enum AudioTrackKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case system
    case microphone
}

public struct AudioTrackMix: Codable, Equatable, Sendable {
    public let kind: AudioTrackKind
    public let volume: Double
    public let isMuted: Bool

    public init(
        kind: AudioTrackKind,
        volume: Double = 1,
        isMuted: Bool = false
    ) {
        self.kind = kind
        self.volume = min(2, max(0, volume))
        self.isMuted = isMuted
    }

    public var gain: Double {
        isMuted ? 0 : volume
    }
}

public struct AudioMixPlan: Codable, Equatable, Sendable {
    public static let normalizationTargetPeak = pow(10.0, -1.0 / 20.0)

    public let tracks: [AudioTrackMix]
    public let normalizePeak: Bool

    public init(
        tracks: [AudioTrackMix] = AudioTrackKind.allCases.map { AudioTrackMix(kind: $0) },
        normalizePeak: Bool = false
    ) {
        self.tracks = Self.deduplicated(tracks)
        self.normalizePeak = normalizePeak
    }

    public var isMuted: Bool {
        tracks.isEmpty || tracks.allSatisfy { $0.gain == 0 }
    }

    public func mix(for kind: AudioTrackKind) -> AudioTrackMix {
        tracks.first { $0.kind == kind } ?? AudioTrackMix(kind: kind, isMuted: true)
    }

    public func resolvedGains(measuredPeaks: [AudioTrackKind: Double] = [:]) -> [AudioTrackKind:
        Double] {
        let baseGains = Dictionary(uniqueKeysWithValues: tracks.map { ($0.kind, $0.gain) })
        guard normalizePeak else {
            return baseGains
        }

        let outputPeak = tracks.reduce(0) { peak, track in
            let measuredPeak = max(0, measuredPeaks[track.kind] ?? 0)
            return max(peak, measuredPeak * track.gain)
        }
        guard outputPeak > 0 else {
            return baseGains
        }

        let normalizationGain = Self.normalizationTargetPeak / outputPeak
        return baseGains.mapValues { $0 * normalizationGain }
    }

    private static func deduplicated(_ tracks: [AudioTrackMix]) -> [AudioTrackMix] {
        var seen: Set<AudioTrackKind> = []
        return tracks.filter { track in
            seen.insert(track.kind).inserted
        }
    }
}
