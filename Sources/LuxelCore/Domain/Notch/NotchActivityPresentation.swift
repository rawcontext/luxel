import Foundation

public struct NotchActivityViewModel: Equatable, Sendable {
    public let collapsedTitle: String
    public let collapsedSystemImage: String
    public let expandedTitle: String
    public let expandedDetail: String?
    public let leadingEarText: String?
    public let trailingEarText: String?
    public let progress: Double?
    public let audioLevel: AudioLevelSample?
    public let artifact: NotchArtifact?
    public let actions: [NotchActivityActionDescriptor]
    public let accessibilityLabel: String

    public init(
        collapsedTitle: String,
        collapsedSystemImage: String,
        expandedTitle: String,
        expandedDetail: String? = nil,
        leadingEarText: String? = nil,
        trailingEarText: String? = nil,
        progress: Double? = nil,
        audioLevel: AudioLevelSample? = nil,
        artifact: NotchArtifact? = nil,
        actions: [NotchActivityActionDescriptor] = [],
        accessibilityLabel: String
    ) {
        self.collapsedTitle = collapsedTitle
        self.collapsedSystemImage = collapsedSystemImage
        self.expandedTitle = expandedTitle
        self.expandedDetail = expandedDetail
        self.leadingEarText = leadingEarText
        self.trailingEarText = trailingEarText
        self.progress = progress
        self.audioLevel = audioLevel
        self.artifact = artifact
        self.actions = actions
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct NotchActivityActionDescriptor: Codable, Equatable, Sendable {
    public let id: NotchActivityActionID
    public let title: String
    public let systemImage: String
    public let role: NotchActivityActionRole

    public init(
        id: NotchActivityActionID,
        title: String,
        systemImage: String,
        role: NotchActivityActionRole = .standard
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
    }
}

public enum NotchActivityActionID: String, Codable, Equatable, Sendable {
    case recordArea
    case recordWindow
    case recordFullscreen
    case screenshot
    case quickGIF
    case openSettings
    case cancel
    case pauseRecording
    case resumeRecording
    case stopRecording
    case discardRecording
    case markMoment
    case toggleMute
    case clipReplay
    case pauseReplayBuffer
    case cancelProcessing
    case cancelExport
    case reveal
    case copy
    case openInEditor
    case openInPreview
    case save
    case retry
    case revealStorage
}

public enum NotchActivityActionRole: String, Codable, Equatable, Sendable {
    case standard
    case primary
    case destructive
}

public enum NotchActivityPresentation {
    public static func viewModel(for activity: NotchActivity) -> NotchActivityViewModel {
        switch activity {
        case .dormant:
            dormantViewModel
        case .idleHover:
            idleHoverViewModel
        case .arming(let remaining):
            armingViewModel(remaining: remaining)
        case .recording(let elapsed, let audioLevel, let muted):
            recordingViewModel(elapsed: elapsed, audioLevel: audioLevel, isMuted: muted)
        case .paused(let elapsed):
            pausedViewModel(elapsed: elapsed)
        case .replayBuffering(let coverage):
            replayBufferingViewModel(coverage: coverage)
        case .processing:
            processingViewModel
        case .exporting(let snapshot):
            exportingViewModel(snapshot: snapshot)
        case .completed(let artifact):
            completedViewModel(artifact: artifact)
        case .screenshotCaptured(let artifact):
            screenshotCapturedViewModel(artifact: artifact)
        case .error(let error):
            errorViewModel(error: error)
        case .nowPlaying(let snapshot):
            nowPlayingViewModel(snapshot: snapshot)
        }
    }

    private static var dormantViewModel: NotchActivityViewModel {
        NotchActivityViewModel(
            collapsedTitle: "",
            collapsedSystemImage: "circle",
            expandedTitle: "Luxel",
            accessibilityLabel: "Luxel notch inactive"
        )
    }

    private static var idleHoverViewModel: NotchActivityViewModel {
        NotchActivityViewModel(
            collapsedTitle: "Luxel",
            collapsedSystemImage: "record.circle",
            expandedTitle: "Luxel",
            expandedDetail: "Ready",
            actions: [
                action(.recordArea, "Record Area", "record.circle"),
                action(.recordWindow, "Record Window", "macwindow"),
                action(.recordFullscreen, "Record Fullscreen", "display"),
                action(.screenshot, "Screenshot", "camera"),
                action(.quickGIF, "Quick GIF", "bolt"),
                action(.openSettings, "Settings", "gear")
            ],
            accessibilityLabel: "Luxel ready"
        )
    }

    private static func armingViewModel(remaining: TimeInterval) -> NotchActivityViewModel {
        let countdown = countdownText(remaining)
        return NotchActivityViewModel(
            collapsedTitle: countdown,
            collapsedSystemImage: "hourglass",
            expandedTitle: "Recording starts in \(countdown)",
            expandedDetail: "Cancel before capture begins",
            actions: [
                action(.cancel, "Cancel", "xmark.circle.fill", role: .destructive)
            ],
            accessibilityLabel: "Luxel recording starts in \(countdown)"
        )
    }

    private static func recordingViewModel(
        elapsed: TimeInterval,
        audioLevel: AudioLevelSample,
        isMuted: Bool
    ) -> NotchActivityViewModel {
        let elapsedText = elapsedTimeText(elapsed)
        return NotchActivityViewModel(
            collapsedTitle: elapsedText,
            collapsedSystemImage: "record.circle.fill",
            expandedTitle: "Recording",
            expandedDetail: "Elapsed \(elapsedText)",
            leadingEarText: elapsedText,
            trailingEarText: isMuted ? "Muted" : "Mic \(levelPercent(audioLevel.peak))",
            audioLevel: isMuted ? nil : audioLevel,
            actions: [
                action(.pauseRecording, "Pause", "pause.circle"),
                action(.stopRecording, "Stop", "stop.circle.fill", role: .destructive),
                action(.markMoment, "Mark Moment", "flag"),
                action(.clipReplay, "Clip Replay", "gobackward"),
                action(.toggleMute, isMuted ? "Unmute" : "Mute", isMuted ? "mic" : "mic.slash")
            ],
            accessibilityLabel: "Luxel recording, elapsed \(elapsedText)"
        )
    }

    private static func pausedViewModel(elapsed: TimeInterval) -> NotchActivityViewModel {
        let elapsedText = elapsedTimeText(elapsed)
        return NotchActivityViewModel(
            collapsedTitle: elapsedText,
            collapsedSystemImage: "pause.circle.fill",
            expandedTitle: "Paused",
            expandedDetail: "Paused at \(elapsedText)",
            leadingEarText: elapsedText,
            trailingEarText: "Paused",
            actions: [
                action(.resumeRecording, "Resume", "play.circle", role: .primary),
                action(.stopRecording, "Stop", "stop.circle.fill", role: .destructive),
                action(.discardRecording, "Discard", "trash", role: .destructive)
            ],
            accessibilityLabel: "Luxel recording paused at \(elapsedText)"
        )
    }

    private static func replayBufferingViewModel(
        coverage: NotchReplayBufferCoverage
    ) -> NotchActivityViewModel {
        let progress = percent(coverage.progress)
        return NotchActivityViewModel(
            collapsedTitle: "Buffer \(progress)",
            collapsedSystemImage: "gobackward",
            expandedTitle: "Replay Buffer",
            expandedDetail: "\(durationText(coverage.coveredDuration)) ready",
            progress: coverage.progress,
            actions: [
                action(.clipReplay, "Clip Replay", "gobackward", role: .primary),
                action(.pauseReplayBuffer, "Pause Buffer", "pause.circle")
            ],
            accessibilityLabel: "Luxel replay buffer \(progress) ready"
        )
    }

    private static var processingViewModel: NotchActivityViewModel {
        NotchActivityViewModel(
            collapsedTitle: "Processing",
            collapsedSystemImage: "progress.indicator",
            expandedTitle: "Finishing Recording",
            expandedDetail: "Preparing the file",
            actions: [
                action(.cancelProcessing, "Cancel", "xmark.circle", role: .destructive)
            ],
            accessibilityLabel: "Luxel finishing recording"
        )
    }

    private static func exportingViewModel(snapshot: ExportProgressSnapshot) -> NotchActivityViewModel {
        let progress = percent(snapshot.progress)
        return NotchActivityViewModel(
            collapsedTitle: progress,
            collapsedSystemImage: "square.and.arrow.up",
            expandedTitle: snapshot.actionTitle,
            expandedDetail: "\(progress) complete",
            progress: snapshot.progress,
            actions: [
                action(.cancelExport, "Cancel Export", "xmark.circle", role: .destructive)
            ],
            accessibilityLabel: "Luxel exporting, \(progress) complete"
        )
    }

    private static func completedViewModel(artifact: NotchArtifact) -> NotchActivityViewModel {
        NotchActivityViewModel(
            collapsedTitle: "Done",
            collapsedSystemImage: "checkmark.circle.fill",
            expandedTitle: completedTitle(for: artifact.kind),
            expandedDetail: artifact.fileURL.lastPathComponent,
            artifact: artifact,
            actions: [
                action(.reveal, "Reveal", "folder"),
                action(.copy, "Copy", "doc.on.doc"),
                action(.openInEditor, "Open in Editor", "rectangle.and.pencil.and.ellipsis")
            ],
            accessibilityLabel: "Luxel completed \(artifact.fileURL.lastPathComponent)"
        )
    }

    private static func screenshotCapturedViewModel(
        artifact: NotchArtifact
    ) -> NotchActivityViewModel {
        NotchActivityViewModel(
            collapsedTitle: "Screenshot",
            collapsedSystemImage: "camera.fill",
            expandedTitle: "Screenshot Captured",
            expandedDetail: artifact.fileURL.lastPathComponent,
            artifact: artifact,
            actions: [
                action(.copy, "Copy", "doc.on.doc"),
                action(.save, "Save", "square.and.arrow.down"),
                action(.openInPreview, "Open in Preview", "eye")
            ],
            accessibilityLabel: "Luxel screenshot captured"
        )
    }

    private static func errorViewModel(error: NotchError) -> NotchActivityViewModel {
        let actions = error.recoveryAction.map { [actionDescriptor(for: $0)] } ?? []
        return NotchActivityViewModel(
            collapsedTitle: "Error",
            collapsedSystemImage: "exclamationmark.triangle.fill",
            expandedTitle: error.title,
            expandedDetail: error.message,
            actions: actions,
            accessibilityLabel: "Luxel error: \(error.title)"
        )
    }

    private static func nowPlayingViewModel(snapshot: NotchNowPlayingSnapshot) -> NotchActivityViewModel {
        let elapsed = elapsedTimeText(snapshot.elapsed)
        let duration = elapsedTimeText(snapshot.duration)
        return NotchActivityViewModel(
            collapsedTitle: elapsed,
            collapsedSystemImage: "play.circle",
            expandedTitle: "Preview",
            expandedDetail: "\(elapsed) of \(duration)",
            progress: snapshot.progress,
            accessibilityLabel: "Luxel preview at \(elapsed) of \(duration)"
        )
    }

    private static func action(
        _ id: NotchActivityActionID,
        _ title: String,
        _ systemImage: String,
        role: NotchActivityActionRole = .standard
    ) -> NotchActivityActionDescriptor {
        NotchActivityActionDescriptor(
            id: id,
            title: title,
            systemImage: systemImage,
            role: role
        )
    }

    private static func actionDescriptor(
        for recoveryAction: NotchRecoveryAction
    ) -> NotchActivityActionDescriptor {
        switch recoveryAction {
        case .openSettings:
            action(.openSettings, "Open Settings", "gear", role: .primary)
        case .retry:
            action(.retry, "Retry", "arrow.clockwise", role: .primary)
        case .revealStorage:
            action(.revealStorage, "Reveal Storage", "folder", role: .primary)
        }
    }

    private static func elapsedTimeText(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }

        return "\(minutes):\(twoDigits(seconds))"
    }

    private static func countdownText(_ remaining: TimeInterval) -> String {
        "\(max(0, Int(remaining.rounded(.up)))) s"
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }

    private static func percent(_ progress: Double) -> String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    private static func levelPercent(_ level: Double) -> String {
        percent(level)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func completedTitle(for kind: NotchArtifactKind) -> String {
        switch kind {
        case .recording:
            "Recording Ready"
        case .export:
            "Export Ready"
        case .screenshot:
            "Screenshot Ready"
        }
    }
}
