import Foundation

public enum AutomationExecutionResult: Equatable, Sendable {
    case accepted
    case recording(id: String)
    case file(URL)
    case resultFile(URL, contentType: String, removeAfterRead: Bool)
}

public enum AutomationServiceResult: Equatable, Sendable {
    case executed(AutomationExecutionResult)
    case requiresConfirmation(AutomationPolicyPrompt)
    case denied(String)
}

public final class AutomationService: Sendable {
    private let executor: any AutomationCommandExecutor

    public init(executor: any AutomationCommandExecutor) {
        self.executor = executor
    }

    public func execute(
        _ invocation: AutomationInvocation,
        settings: AppSettings,
        context: AutomationPolicyContext
    ) async throws -> AutomationServiceResult {
        switch AutomationPolicy.evaluate(
            command: invocation.command, settings: settings, context: context) {
        case .allow:
            return .executed(try await execute(invocation.command))
        case .confirm(let prompt):
            return .requiresConfirmation(prompt)
        case .deny(let reason):
            return .denied(reason)
        }
    }

    public func executeConfirmed(_ invocation: AutomationInvocation) async throws
        -> AutomationExecutionResult {
        try await execute(invocation.command)
    }

    private func execute(_ command: AutomationCommand) async throws -> AutomationExecutionResult {
        switch command {
        case .record(let options):
            try await executor.record(options)
        case .stop:
            try await executor.stop()
        case .toggle(let options):
            try await executor.toggle(options)
        case .clip(let seconds):
            try await executor.clipReplayBuffer(seconds: seconds)
        case .preferences(let pane):
            try await executor.openPreferences(pane)
        case .latest(let reveal):
            try await executor.openLatestRecording(reveal: reveal)
        case .transcribe(let options):
            try await executor.transcribe(options)
        }
    }
}
