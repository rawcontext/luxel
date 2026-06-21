import Foundation

public protocol AutomationCommandExecutor: Sendable {
    func record(_ options: AutomationRecordingOptions) async throws -> AutomationExecutionResult
    func stop() async throws -> AutomationExecutionResult
    func toggle(_ options: AutomationRecordingOptions?) async throws -> AutomationExecutionResult
    func clipReplayBuffer(seconds: Int?) async throws -> AutomationExecutionResult
    func openPreferences(_ pane: AutomationPreferencesPane?) async throws -> AutomationExecutionResult
    func openLatestRecording(reveal: Bool) async throws -> AutomationExecutionResult
}
