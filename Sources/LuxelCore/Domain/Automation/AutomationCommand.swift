import Foundation

public struct AutomationInvocation: Equatable, Sendable {
    public let command: AutomationCommand
    public let callbacks: AutomationCallbacks

    public init(
        command: AutomationCommand,
        callbacks: AutomationCallbacks = AutomationCallbacks()
    ) {
        self.command = command
        self.callbacks = callbacks
    }
}

public struct AutomationCallbacks: Equatable, Sendable {
    public let success: URL?
    public let error: URL?

    public init(success: URL? = nil, error: URL? = nil) {
        self.success = success
        self.error = error
    }
}

public enum AutomationCallbackURLBuilder {
    public static func successURL(
        for result: AutomationExecutionResult,
        callback: URL?
    ) -> URL? {
        guard let callback else {
            return nil
        }

        switch result {
        case .accepted:
            return callback
        case .recording(let id):
            return appendingQueryItem(name: "recordingID", value: id, to: callback)
        case .file(let url):
            return appendingQueryItem(name: "filePath", value: url.path, to: callback)
        }
    }

    public static func errorURL(message: String, callback: URL?) -> URL? {
        guard let callback else {
            return nil
        }

        return appendingQueryItem(name: "errorMessage", value: message, to: callback)
    }

    private static func appendingQueryItem(name: String, value: String, to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url ?? url
    }
}

public enum AutomationCommand: Equatable, Sendable {
    case record(AutomationRecordingOptions)
    case stop
    case toggle(AutomationRecordingOptions?)
    case screenshot(AutomationScreenshotOptions)
    case clip(seconds: Int?)
    case preferences(AutomationPreferencesPane?)
    case latest(reveal: Bool)

    public func requiresAutomationPermission(hasActiveRecording: Bool) -> Bool {
        switch self {
        case .preferences, .stop, .latest:
            false
        case .toggle:
            !hasActiveRecording
        case .record, .screenshot, .clip:
            true
        }
    }

    public func requiresStartConfirmation(hasActiveRecording: Bool) -> Bool {
        switch self {
        case .record, .screenshot, .clip:
            true
        case .toggle:
            !hasActiveRecording
        case .preferences, .stop, .latest:
            false
        }
    }

    var actionDescription: String {
        switch self {
        case .record:
            "start a screen recording"
        case .stop:
            "stop recording"
        case .toggle:
            "toggle recording"
        case .screenshot:
            "capture a screenshot"
        case .clip:
            "clip the replay buffer"
        case .preferences:
            "open Luxel settings"
        case .latest:
            "open the latest recording"
        }
    }
}

public struct AutomationRecordingOptions: Equatable, Sendable {
    public let target: AutomationCaptureTarget
    public let presetName: String?
    public let countdownSeconds: Int?

    public init(
        target: AutomationCaptureTarget,
        presetName: String? = nil,
        countdownSeconds: Int? = nil
    ) {
        self.target = target
        self.presetName = presetName
        self.countdownSeconds = countdownSeconds
    }
}

public struct AutomationScreenshotOptions: Equatable, Sendable {
    public let target: AutomationCaptureTarget
    public let format: ScreenshotFormat?

    public init(target: AutomationCaptureTarget, format: ScreenshotFormat? = nil) {
        self.target = target
        self.format = format
    }
}

public enum AutomationCaptureTarget: Equatable, Sendable {
    case display(AutomationDisplayTarget)
    case activeWindow
    case lastArea
}

public enum AutomationDisplayTarget: Equatable, Sendable {
    case main
    case id(String)
}

public enum AutomationPreferencesPane: String, CaseIterable, Equatable, Sendable {
    case general
    case presets
    case shortcuts
    case screenshots
    case updates
    case about
}

public enum AutomationCommandParseError: Error, Equatable {
    case unsupportedScheme(String?)
    case missingAction
    case unknownAction(String)
    case missingParameter(String)
    case invalidParameter(String)
    case duplicateParameter(String)
    case invalidCallbackURL(String)
}

public enum AutomationCommandParser {
    public static func parse(_ url: URL) throws -> AutomationInvocation {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AutomationCommandParseError.unsupportedScheme(url.scheme)
        }

        guard components.scheme?.lowercased() == "luxel" else {
            throw AutomationCommandParseError.unsupportedScheme(components.scheme)
        }

        let query = try AutomationQuery(components.queryItems)
        let command = try parseCommand(action: action(from: components), query: query)
        return AutomationInvocation(
            command: command,
            callbacks: try AutomationCallbacks(
                success: callbackURL(named: "x-success", in: query),
                error: callbackURL(named: "x-error", in: query)
            )
        )
    }

    private static func action(from components: URLComponents) throws -> String {
        if let host = components.host, !host.isEmpty {
            return host
        }

        if let pathAction = components.path
            .split(separator: "/")
            .first
            .map(String.init),
           !pathAction.isEmpty {
            return pathAction
        }

        throw AutomationCommandParseError.missingAction
    }

    private static func parseCommand(
        action: String,
        query: AutomationQuery
    ) throws -> AutomationCommand {
        switch action.lowercased() {
        case "record":
            return .record(try recordingOptions(query: query, targetRequired: true))
        case "stop":
            return .stop
        case "toggle":
            let options = query.value(for: "target") == nil
                ? nil
                : try recordingOptions(query: query, targetRequired: true)
            return .toggle(options)
        case "screenshot":
            return .screenshot(try screenshotOptions(query: query))
        case "clip":
            return .clip(seconds: try optionalPositiveInteger("seconds", in: query))
        case "preferences":
            return .preferences(try preferencesPane(in: query))
        case "latest":
            return .latest(reveal: try optionalBoolean("reveal", in: query) ?? false)
        default:
            throw AutomationCommandParseError.unknownAction(action)
        }
    }

    private static func recordingOptions(
        query: AutomationQuery,
        targetRequired: Bool
    ) throws -> AutomationRecordingOptions {
        guard let target = try captureTarget(in: query, required: targetRequired) else {
            throw AutomationCommandParseError.missingParameter("target")
        }

        return AutomationRecordingOptions(
            target: target,
            presetName: nonEmpty(query.value(for: "preset")),
            countdownSeconds: try optionalCountdownInteger(in: query)
        )
    }

    private static func screenshotOptions(query: AutomationQuery) throws -> AutomationScreenshotOptions {
        let format = try screenshotFormat(in: query)
        guard let target = try captureTarget(in: query, required: true) else {
            throw AutomationCommandParseError.missingParameter("target")
        }

        return AutomationScreenshotOptions(target: target, format: format)
    }

    private static func captureTarget(
        in query: AutomationQuery,
        required: Bool
    ) throws -> AutomationCaptureTarget? {
        guard let target = query.value(for: "target") else {
            if required {
                throw AutomationCommandParseError.missingParameter("target")
            }

            return nil
        }

        switch target.lowercased() {
        case "display":
            guard let display = nonEmpty(query.value(for: "display")) else {
                throw AutomationCommandParseError.missingParameter("display")
            }

            return .display(display.lowercased() == "main" ? .main : .id(display))
        case "activewindow":
            return .activeWindow
        case "lastarea":
            return .lastArea
        default:
            throw AutomationCommandParseError.invalidParameter("target")
        }
    }

    private static func screenshotFormat(in query: AutomationQuery) throws -> ScreenshotFormat? {
        guard let format = query.value(for: "format") else {
            return nil
        }

        guard let screenshotFormat = ScreenshotFormat(rawValue: format.lowercased()) else {
            throw AutomationCommandParseError.invalidParameter("format")
        }

        return screenshotFormat
    }

    private static func preferencesPane(in query: AutomationQuery) throws -> AutomationPreferencesPane? {
        guard let pane = query.value(for: "pane") else {
            return nil
        }

        guard let preferencesPane = AutomationPreferencesPane(rawValue: pane.lowercased()) else {
            throw AutomationCommandParseError.invalidParameter("pane")
        }

        return preferencesPane
    }

    private static func optionalNonNegativeInteger(
        _ name: String,
        in query: AutomationQuery
    ) throws -> Int? {
        guard let value = query.value(for: name) else {
            return nil
        }

        guard let integer = Int(value), integer >= 0 else {
            throw AutomationCommandParseError.invalidParameter(name)
        }

        return integer
    }

    private static func optionalCountdownInteger(in query: AutomationQuery) throws -> Int? {
        guard let integer = try optionalNonNegativeInteger("countdown", in: query) else {
            return nil
        }

        guard (0...60).contains(integer) else {
            throw AutomationCommandParseError.invalidParameter("countdown")
        }

        return integer
    }

    private static func optionalPositiveInteger(
        _ name: String,
        in query: AutomationQuery
    ) throws -> Int? {
        guard let value = query.value(for: name) else {
            return nil
        }

        guard let integer = Int(value), integer > 0 else {
            throw AutomationCommandParseError.invalidParameter(name)
        }

        return integer
    }

    private static func optionalBoolean(
        _ name: String,
        in query: AutomationQuery
    ) throws -> Bool? {
        guard let value = query.value(for: name) else {
            return nil
        }

        switch value.lowercased() {
        case "true", "1":
            return true
        case "false", "0":
            return false
        default:
            throw AutomationCommandParseError.invalidParameter(name)
        }
    }

    private static func callbackURL(
        named name: String,
        in query: AutomationQuery
    ) throws -> URL? {
        guard let value = query.value(for: name) else {
            return nil
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              !url.isFileURL,
              scheme != "file" else {
            throw AutomationCommandParseError.invalidCallbackURL(name)
        }

        return url
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }
}

private struct AutomationQuery {
    private let values: [String: String]

    init(_ queryItems: [URLQueryItem]?) throws {
        var values: [String: String] = [:]
        for item in queryItems ?? [] {
            guard values[item.name] == nil else {
                throw AutomationCommandParseError.duplicateParameter(item.name)
            }

            values[item.name] = item.value ?? ""
        }

        self.values = values
    }

    func value(for name: String) -> String? {
        values[name]
    }
}

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

        guard settings.allowURLAutomation else {
            return .deny("URL automation is disabled")
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
