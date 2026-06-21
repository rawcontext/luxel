import Foundation

public enum NotchPresentationState: String, Codable, Equatable, Sendable {
    case collapsed
    case expanded
}

public enum NotchActivity: Equatable, Sendable {
    case dormant
    case idleHover
    case arming(remaining: TimeInterval)
    case recording(elapsed: TimeInterval, audioLevel: AudioLevelSample, muted: Bool)
    case paused(elapsed: TimeInterval)
    case replayBuffering(coverage: NotchReplayBufferCoverage)
    case processing
    case exporting(snapshot: ExportProgressSnapshot)
    case completed(artifact: NotchArtifact)
    case error(NotchError)
    case nowPlaying(NotchNowPlayingSnapshot)

    public var isTransient: Bool {
        switch self {
        case .completed, .error:
            true
        case .dormant, .idleHover, .arming, .recording, .paused, .replayBuffering, .processing,
             .exporting,
             .nowPlaying:
            false
        }
    }

    fileprivate var priority: Int {
        switch self {
        case .error:
            110
        case .completed:
            100
        case .exporting:
            90
        case .processing:
            80
        case .recording:
            70
        case .arming:
            65
        case .paused:
            60
        case .replayBuffering:
            50
        case .nowPlaying:
            30
        case .idleHover:
            10
        case .dormant:
            0
        }
    }
}

public struct NotchReplayBufferCoverage: Codable, Equatable, Sendable {
    public let coveredDuration: TimeInterval
    public let requestedDuration: TimeInterval

    public init(coveredDuration: TimeInterval, requestedDuration: TimeInterval) throws {
        guard coveredDuration.isFinite, coveredDuration >= 0,
              requestedDuration.isFinite, requestedDuration > 0
        else {
            throw NotchActivityError.invalidReplayCoverage
        }

        self.coveredDuration = min(coveredDuration, requestedDuration)
        self.requestedDuration = requestedDuration
    }

    public init(_ coverage: ReplayBufferClipCoverage) throws {
        try self.init(
            coveredDuration: coverage.coveredDuration,
            requestedDuration: coverage.requestedDuration
        )
    }

    public var progress: Double {
        min(coveredDuration / requestedDuration, 1)
    }
}

public enum NotchArtifactKind: String, Codable, Equatable, Sendable {
    case recording
    case export
}

public struct NotchArtifact: Codable, Equatable, Sendable {
    public let fileURL: URL
    public let thumbnailURL: URL?
    public let kind: NotchArtifactKind

    public init(fileURL: URL, thumbnailURL: URL? = nil, kind: NotchArtifactKind) {
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.kind = kind
    }
}

public enum NotchRecoveryAction: String, Codable, Equatable, Sendable {
    case openSettings
    case retry
    case revealStorage
}

public struct NotchError: Codable, Equatable, Sendable {
    public let title: String
    public let message: String
    public let recoveryAction: NotchRecoveryAction?

    public init(
        title: String,
        message: String,
        recoveryAction: NotchRecoveryAction? = nil
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedMessage.isEmpty else {
            throw NotchActivityError.emptyErrorText
        }

        self.title = trimmedTitle
        self.message = trimmedMessage
        self.recoveryAction = recoveryAction
    }
}

public struct NotchNowPlayingSnapshot: Codable, Equatable, Sendable {
    public let elapsed: TimeInterval
    public let duration: TimeInterval

    public init(elapsed: TimeInterval, duration: TimeInterval) throws {
        guard elapsed.isFinite, elapsed >= 0,
              duration.isFinite, duration > 0
        else {
            throw NotchActivityError.invalidPlaybackTime
        }

        self.elapsed = min(elapsed, duration)
        self.duration = duration
    }

    public var progress: Double {
        elapsed / duration
    }
}

public enum NotchActivityResolver {
    public static func resolve(_ activities: [NotchActivity]) -> NotchActivity {
        activities.reduce(.dormant) { current, candidate in
            candidate.priority > current.priority ? candidate : current
        }
    }

    public static func yieldTransient(
        _ activity: NotchActivity,
        to previousSteadyActivity: NotchActivity
    ) -> NotchActivity {
        guard activity.isTransient else {
            return activity
        }

        return previousSteadyActivity.isTransient ? .dormant : previousSteadyActivity
    }
}

public enum NotchActivityError: Error, Equatable {
    case invalidReplayCoverage
    case emptyErrorText
    case invalidPlaybackTime
}
