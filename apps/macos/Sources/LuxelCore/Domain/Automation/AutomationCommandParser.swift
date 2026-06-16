import Foundation

public enum AutomationCommandParseError: Error, Equatable {
    case unsupportedScheme(String?)
    case missingAction
    case unknownAction(String)
    case missingParameter(String)
    case invalidParameter(String)
    case duplicateParameter(String)
    case invalidCallbackURL(String)
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
            countdownSeconds: try optionalCountdownInteger(in: query),
            outputDirectory: try optionalOutputDirectory(in: query)
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

    private static func optionalOutputDirectory(in query: AutomationQuery) throws -> URL? {
        guard let value = nonEmpty(query.value(for: "saveTo")) else {
            return nil
        }

        if let url = URL(string: value),
           url.isFileURL,
           !url.path.isEmpty {
            return url.standardizedFileURL
        }

        let expandedPath = (value as NSString).expandingTildeInPath
        guard expandedPath.hasPrefix("/") else {
            throw AutomationCommandParseError.invalidParameter("saveTo")
        }

        return URL(fileURLWithPath: expandedPath).standardizedFileURL
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
