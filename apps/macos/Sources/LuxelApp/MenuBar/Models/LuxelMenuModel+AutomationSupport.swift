import AppKit
import Foundation
import LuxelCore

struct AutomationResolvedCaptureTarget {
    let target: CaptureTarget
    let pixelSize: PixelSize

    init(target: CaptureTarget, pixelSize: PixelSize) {
        self.target = target
        self.pixelSize = pixelSize
    }

    init(option: CaptureTargetOption) {
        self.init(target: option.target, pixelSize: option.pixelSize)
    }
}

enum LuxelAutomationURLCaller {
    static let genericID = "luxel-url-generic"
    static let genericDisplayName = "A URL automation"
}

final class LuxelAutomationCommandExecutor: AutomationCommandExecutor, @unchecked Sendable {
    private let execute: @MainActor @Sendable (AutomationCommand) async throws -> AutomationExecutionResult

    init(
        execute:
            @escaping @MainActor @Sendable (AutomationCommand) async throws -> AutomationExecutionResult
    ) {
        self.execute = execute
    }

    func record(_ options: AutomationRecordingOptions) async throws -> AutomationExecutionResult {
        try await execute(.record(options))
    }

    func stop() async throws -> AutomationExecutionResult {
        try await execute(.stop)
    }

    func toggle(_ options: AutomationRecordingOptions?) async throws -> AutomationExecutionResult {
        try await execute(.toggle(options))
    }

    func clipReplayBuffer(seconds: Int?) async throws -> AutomationExecutionResult {
        try await execute(.clip(seconds: seconds))
    }

    func openPreferences(_ pane: AutomationPreferencesPane?) async throws -> AutomationExecutionResult {
        try await execute(.preferences(pane))
    }

    func openLatestRecording(reveal: Bool) async throws -> AutomationExecutionResult {
        try await execute(.latest(reveal: reveal))
    }

    func transcribe(_ options: AutomationTranscriptionOptions) async throws
        -> AutomationExecutionResult
    {
        try await execute(.transcribe(options))
    }
}

enum LuxelAutomationError: LocalizedError, Equatable {
    case denied
    case noRecentRecording
    case noQuickExportPreset
    case presetUnavailable(String)
    case quickExportFailed
    case replayBufferUnavailable
    case targetUnavailable
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            "URL automation was denied"
        case .noRecentRecording:
            "No recent recording is available"
        case .noQuickExportPreset:
            "No quick export preset is selected"
        case .presetUnavailable(let name):
            "No export preset named \(name)"
        case .quickExportFailed:
            "Replay buffer quick export failed"
        case .replayBufferUnavailable:
            "Replay buffer automation is unavailable until the replay buffer engine is available"
        case .targetUnavailable:
            "No matching capture target is available"
        case .unavailable:
            "URL automation is unavailable"
        }
    }
}
