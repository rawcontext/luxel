import AppKit
import Foundation
import LuxelCore

struct AutomationURLPrompt: Equatable {
    let prompt: AutomationPolicyPrompt
    let invocation: AutomationInvocation
    let context: AutomationPolicyContext
}

@MainActor
extension LuxelMenuModel {
    func handleAutomationURL(
        _ url: URL,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async {
        do {
            let invocation = try AutomationCommandParser.parse(url)
            let context = AutomationPolicyContext(
                callerID: LuxelAutomationURLCaller.genericID,
                callerDisplayName: LuxelAutomationURLCaller.genericDisplayName,
                hasActiveRecording: hasActiveRecording
            )
            try await executeAutomationInvocation(
                invocation,
                context: context,
                bypassingPolicy: false,
                openSettings: openSettings,
                openRecording: openRecording
            )
        } catch {
            reportAutomationError(error, callback: nil)
        }
    }

    func approveAutomationPrompt(
        alwaysAllow: Bool,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async {
        guard let automationPrompt else {
            return
        }

        self.automationPrompt = nil

        if alwaysAllow,
           let callerID = automationPrompt.context.callerID,
           !settings.urlAutomationGrants.contains(callerID) {
            settings.allowURLAutomation = true
            settings.urlAutomationGrants.append(callerID)
            saveSettings()
        }

        do {
            try await executeAutomationInvocation(
                automationPrompt.invocation,
                context: automationPrompt.context,
                bypassingPolicy: true,
                openSettings: openSettings,
                openRecording: openRecording
            )
        } catch {
            reportAutomationError(error, callback: automationPrompt.invocation.callbacks.error)
        }
    }

    func denyAutomationPrompt() {
        guard let automationPrompt else {
            return
        }

        self.automationPrompt = nil
        reportAutomationError(
            LuxelAutomationError.denied,
            callback: automationPrompt.invocation.callbacks.error
        )
    }

    private func executeAutomationInvocation(
        _ invocation: AutomationInvocation,
        context: AutomationPolicyContext,
        bypassingPolicy: Bool,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws {
        let executor = LuxelAutomationCommandExecutor { [weak self] command in
            guard let self else {
                throw LuxelAutomationError.unavailable
            }

            return try await self.executeAutomationCommand(
                command,
                openSettings: openSettings,
                openRecording: openRecording
            )
        }
        let service = AutomationService(executor: executor)

        if bypassingPolicy {
            let result = try await service.executeConfirmed(invocation)
            handleAutomationSuccess(result, callback: invocation.callbacks.success)
            return
        }

        switch try await service.execute(invocation, settings: settings, context: context) {
        case .executed(let result):
            handleAutomationSuccess(result, callback: invocation.callbacks.success)
        case .requiresConfirmation(let prompt):
            automationPrompt = AutomationURLPrompt(
                prompt: prompt,
                invocation: invocation,
                context: context
            )
        case .denied(let reason):
            reportAutomationError(reason, callback: invocation.callbacks.error)
        }
    }

    private func executeAutomationCommand(
        _ command: AutomationCommand,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws -> AutomationExecutionResult {
        switch command {
        case .record(let options):
            try await startAutomationRecording(options)
            return .accepted
        case .stop:
            return await stopAutomationRecording(openRecording: openRecording)
        case .toggle(let options):
            if hasActiveRecording {
                return await stopAutomationRecording(openRecording: openRecording)
            }

            if let options {
                try await startAutomationRecording(options)
            } else {
                try await startAutomationRecording(
                    AutomationRecordingOptions(target: .lastArea)
                )
            }
            return .accepted
        case .screenshot(let options):
            let target = try await resolveAutomationTarget(options.target).target
            return try await captureAutomationScreenshot(target: target, format: options.format)
        case .clip:
            throw LuxelAutomationError.replayBufferUnavailable
        case .preferences:
            openSettings()
            return .accepted
        }
    }

    private func startAutomationRecording(_ options: AutomationRecordingOptions) async throws {
        if let countdownSeconds = options.countdownSeconds,
           countdownSeconds > 0 {
            throw LuxelAutomationError.countdownUnavailable
        }

        let presetID = try automationPresetID(named: options.presetName)

        if options.target == .lastArea {
            await startAutomationRecordingFromLastCapture(presetID: presetID)
            return
        }

        let target = try await resolveAutomationTarget(options.target)
        await startAutomationRecording(
            target: target.target,
            pixelSize: target.pixelSize,
            presetID: presetID
        )
    }

    private func stopAutomationRecording(
        openRecording: @escaping @MainActor (URL) -> Void
    ) async -> AutomationExecutionResult {
        guard let stopAction = await stopRecording() else {
            return .accepted
        }

        switch stopAction {
        case .openEditor(let fileURL):
            openRecording(fileURL)
            return .file(fileURL)
        case .quickExported(let fileURL), .audioRecorded(let fileURL):
            return .file(fileURL)
        }
    }

    private func resolveAutomationTarget(
        _ target: AutomationCaptureTarget
    ) async throws -> AutomationResolvedCaptureTarget {
        await refreshCaptureTargets()

        switch target {
        case .display(.main):
            guard let displayTarget = fullscreenCaptureTarget ?? lastCaptureFallbackDisplay else {
                throw LuxelAutomationError.targetUnavailable
            }

            return AutomationResolvedCaptureTarget(option: displayTarget)
        case .display(.id(let id)):
            guard let displayTarget = captureTargets.first(where: { option in
                guard case .display(let displayID) = option.target else {
                    return false
                }

                return String(displayID.rawValue) == id || option.id == id || option.id == "display-\(id)"
            }) else {
                throw LuxelAutomationError.targetUnavailable
            }

            return AutomationResolvedCaptureTarget(option: displayTarget)
        case .activeWindow:
            guard let windowTarget = activeWindowCaptureTargetResolver.resolve(
                from: captureTargets,
                orderedWindowIDs: activeWindowCatalog.orderedActiveWindowIDs()
            ) else {
                throw LuxelAutomationError.targetUnavailable
            }

            return AutomationResolvedCaptureTarget(option: windowTarget)
        case .lastArea:
            guard let resolution = settings.lastCaptureMemory?.resolvedTarget(
                availableTargets: captureTargets,
                fallbackDisplay: lastCaptureFallbackDisplay
            ) else {
                throw LuxelAutomationError.targetUnavailable
            }

            return AutomationResolvedCaptureTarget(
                target: resolution.target,
                pixelSize: resolution.pixelSize
            )
        }
    }

    private func automationPresetID(named name: String?) throws -> UUID? {
        guard let name else {
            return nil
        }

        guard let preset = settings.exportPresets.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw LuxelAutomationError.presetUnavailable(name)
        }

        return preset.id
    }

    private func handleAutomationSuccess(_ result: AutomationExecutionResult, callback: URL?) {
        recordingActionErrorMessage = nil
        if let callbackURL = AutomationCallbackURLBuilder.successURL(for: result, callback: callback) {
            NSWorkspace.shared.open(callbackURL)
        }
    }

    private func reportAutomationError(_ error: Error, callback: URL?) {
        reportAutomationError(errorMessage(error), callback: callback)
    }

    private func reportAutomationError(_ message: String, callback: URL?) {
        recordingActionErrorMessage = message
        if let callbackURL = AutomationCallbackURLBuilder.errorURL(message: message, callback: callback) {
            NSWorkspace.shared.open(callbackURL)
        }
    }
}

private struct AutomationResolvedCaptureTarget {
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

private enum LuxelAutomationURLCaller {
    static let genericID = "luxel-url-generic"
    static let genericDisplayName = "A URL automation"
}

private final class LuxelAutomationCommandExecutor: AutomationCommandExecutor, @unchecked Sendable {
    private let execute: @MainActor @Sendable (AutomationCommand) async throws -> AutomationExecutionResult

    init(
        execute: @escaping @MainActor @Sendable (AutomationCommand) async throws -> AutomationExecutionResult
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

    func captureScreenshot(_ options: AutomationScreenshotOptions) async throws -> AutomationExecutionResult {
        try await execute(.screenshot(options))
    }

    func clipReplayBuffer(seconds: Int?) async throws -> AutomationExecutionResult {
        try await execute(.clip(seconds: seconds))
    }

    func openPreferences(_ pane: AutomationPreferencesPane?) async throws -> AutomationExecutionResult {
        try await execute(.preferences(pane))
    }
}

private enum LuxelAutomationError: LocalizedError, Equatable {
    case countdownUnavailable
    case denied
    case presetUnavailable(String)
    case replayBufferUnavailable
    case targetUnavailable
    case unavailable

    var errorDescription: String? {
        switch self {
        case .countdownUnavailable:
            "Countdown URL automation is not implemented yet"
        case .denied:
            "URL automation was denied"
        case .presetUnavailable(let name):
            "No export preset named \(name)"
        case .replayBufferUnavailable:
            "Replay buffer automation is not implemented yet"
        case .targetUnavailable:
            "No matching capture target is available"
        case .unavailable:
            "URL automation is unavailable"
        }
    }
}
