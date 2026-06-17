import Foundation
import LuxelCore
import Testing

@Suite("Automation service")
struct AutomationServiceTests {
    @Test("ungranted start commands request confirmation by default")
    func ungrantedStartCommandsRequestConfirmationByDefault() async throws {
        let executor = SpyAutomationCommandExecutor()
        let service = AutomationService(executor: executor)
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        let result = try await service.execute(
            AutomationInvocation(command: .record(AutomationRecordingOptions(target: .lastArea))),
            settings: settings,
            context: AutomationPolicyContext()
        )

        #expect(result == .requiresConfirmation(AutomationPolicyPrompt(
            title: "Allow URL Automation?",
            message: "Another app wants to start a screen recording."
        )))
        #expect(executor.calls.isEmpty)
    }

    @Test("ungranted start commands request confirmation without executing")
    func ungrantedStartCommandsRequestConfirmationWithoutExecuting() async throws {
        let executor = SpyAutomationCommandExecutor()
        let service = AutomationService(executor: executor)
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        let result = try await service.execute(
            AutomationInvocation(command: .screenshot(AutomationScreenshotOptions(target: .activeWindow))),
            settings: settings,
            context: AutomationPolicyContext(
                callerID: "com.example.terminal",
                callerDisplayName: "Terminal"
            )
        )

        #expect(result == .requiresConfirmation(AutomationPolicyPrompt(
            title: "Allow URL Automation?",
            message: "Terminal wants to capture a screenshot."
        )))
        #expect(executor.calls.isEmpty)
    }

    @Test("safe commands execute by default")
    func safeCommandsExecuteByDefault() async throws {
        let executor = SpyAutomationCommandExecutor()
        let service = AutomationService(executor: executor)
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        let stopResult = try await service.execute(
            AutomationInvocation(command: .stop),
            settings: settings,
            context: AutomationPolicyContext()
        )
        let preferencesResult = try await service.execute(
            AutomationInvocation(command: .preferences(.presets)),
            settings: settings,
            context: AutomationPolicyContext()
        )
        let latestResult = try await service.execute(
            AutomationInvocation(command: .latest(reveal: true)),
            settings: settings,
            context: AutomationPolicyContext()
        )
        let toggleResult = try await service.execute(
            AutomationInvocation(command: .toggle(nil)),
            settings: settings,
            context: AutomationPolicyContext(hasActiveRecording: true)
        )

        #expect(stopResult == .executed(.accepted))
        #expect(preferencesResult == .executed(.accepted))
        #expect(latestResult == .executed(.accepted))
        #expect(toggleResult == .executed(.accepted))
        #expect(executor.calls == [.stop, .preferences(.presets), .latest(reveal: true), .toggle(nil)])
    }

    @Test("granted commands dispatch to matching executor methods")
    func grantedCommandsDispatchToMatchingExecutorMethods() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/luxel.png")
        let executor = SpyAutomationCommandExecutor(result: .file(fileURL))
        let service = AutomationService(executor: executor)
        let settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            allowURLAutomation: true,
            urlAutomationGrants: ["com.example.terminal"]
        )
        let context = AutomationPolicyContext(callerID: "com.example.terminal")
        let recordOptions = AutomationRecordingOptions(
            target: .display(.main),
            presetName: "Quick GIF",
            countdownSeconds: 3
        )
        let screenshotOptions = AutomationScreenshotOptions(target: .activeWindow, format: .png)

        let recordResult = try await service.execute(
            AutomationInvocation(command: .record(recordOptions)),
            settings: settings,
            context: context
        )
        let toggleResult = try await service.execute(
            AutomationInvocation(command: .toggle(recordOptions)),
            settings: settings,
            context: context
        )
        let screenshotResult = try await service.execute(
            AutomationInvocation(command: .screenshot(screenshotOptions)),
            settings: settings,
            context: context
        )
        let clipResult = try await service.execute(
            AutomationInvocation(command: .clip(seconds: 30)),
            settings: settings,
            context: context
        )

        #expect(recordResult == .executed(.file(fileURL)))
        #expect(toggleResult == .executed(.file(fileURL)))
        #expect(screenshotResult == .executed(.file(fileURL)))
        #expect(clipResult == .executed(.file(fileURL)))
        #expect(executor.calls == [
            .record(recordOptions),
            .toggle(recordOptions),
            .screenshot(screenshotOptions),
            .clip(seconds: 30)
        ])
    }

    @Test("executor errors propagate")
    func executorErrorsPropagate() async throws {
        let executor = SpyAutomationCommandExecutor(error: StubAutomationExecutorError.failed)
        let service = AutomationService(executor: executor)
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        await #expect(throws: StubAutomationExecutorError.failed) {
            _ = try await service.execute(
                AutomationInvocation(command: .stop),
                settings: settings,
                context: AutomationPolicyContext()
            )
        }
        #expect(executor.calls == [.stop])
    }

    @Test("confirmed commands bypass policy and execute")
    func confirmedCommandsBypassPolicyAndExecute() async throws {
        let executor = SpyAutomationCommandExecutor()
        let service = AutomationService(executor: executor)
        let options = AutomationRecordingOptions(target: .lastArea)

        let result = try await service.executeConfirmed(
            AutomationInvocation(command: .record(options))
        )

        #expect(result == .accepted)
        #expect(executor.calls == [.record(options)])
    }
}

private enum StubAutomationExecutorError: Error, Equatable {
    case failed
}

private final class SpyAutomationCommandExecutor: AutomationCommandExecutor, @unchecked Sendable {
    enum Call: Equatable {
        case record(AutomationRecordingOptions)
        case stop
        case toggle(AutomationRecordingOptions?)
        case screenshot(AutomationScreenshotOptions)
        case clip(seconds: Int?)
        case preferences(AutomationPreferencesPane?)
        case latest(reveal: Bool)
    }

    private let result: AutomationExecutionResult
    private let error: (any Error)?
    private(set) var calls: [Call] = []

    init(
        result: AutomationExecutionResult = .accepted,
        error: (any Error)? = nil
    ) {
        self.result = result
        self.error = error
    }

    func record(_ options: AutomationRecordingOptions) async throws -> AutomationExecutionResult {
        try execute(.record(options))
    }

    func stop() async throws -> AutomationExecutionResult {
        try execute(.stop)
    }

    func toggle(_ options: AutomationRecordingOptions?) async throws -> AutomationExecutionResult {
        try execute(.toggle(options))
    }

    func captureScreenshot(_ options: AutomationScreenshotOptions) async throws -> AutomationExecutionResult {
        try execute(.screenshot(options))
    }

    func clipReplayBuffer(seconds: Int?) async throws -> AutomationExecutionResult {
        try execute(.clip(seconds: seconds))
    }

    func openPreferences(_ pane: AutomationPreferencesPane?) async throws -> AutomationExecutionResult {
        try execute(.preferences(pane))
    }

    func openLatestRecording(reveal: Bool) async throws -> AutomationExecutionResult {
        try execute(.latest(reveal: reveal))
    }

    private func execute(_ call: Call) throws -> AutomationExecutionResult {
        calls.append(call)
        if let error {
            throw error
        }

        return result
    }
}
