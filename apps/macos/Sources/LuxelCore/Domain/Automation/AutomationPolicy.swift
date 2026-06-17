import Foundation

public struct AutomationPolicyContext: Equatable, Sendable {
    public let callerID: String?
    public let callerDisplayName: String?
    public let hasActiveRecording: Bool

    public init(
        callerID: String? = nil,
        callerDisplayName: String? = nil,
        hasActiveRecording: Bool = false
    ) {
        self.callerID = callerID
        self.callerDisplayName = callerDisplayName
        self.hasActiveRecording = hasActiveRecording
    }
}

public enum AutomationPolicyDecision: Equatable, Sendable {
    case allow
    case confirm(AutomationPolicyPrompt)
    case deny(String)
}

public struct AutomationPolicyPrompt: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public enum AutomationPolicy {
    public static func evaluate(
        command: AutomationCommand,
        settings: AppSettings,
        context: AutomationPolicyContext
    ) -> AutomationPolicyDecision {
        guard command.requiresAutomationPermission(hasActiveRecording: context.hasActiveRecording) else {
            return .allow
        }

        if let callerID = context.callerID,
           settings.urlAutomationGrants.contains(callerID) {
            return .allow
        }

        if command.requiresStartConfirmation(hasActiveRecording: context.hasActiveRecording) {
            return .confirm(prompt(for: command, context: context))
        }

        return .allow
    }

    private static func prompt(
        for command: AutomationCommand,
        context: AutomationPolicyContext
    ) -> AutomationPolicyPrompt {
        let callerName = context.callerDisplayName ?? "Another app"
        return AutomationPolicyPrompt(
            title: "Allow URL Automation?",
            message: "\(callerName) wants to \(command.actionDescription)."
        )
    }
}
