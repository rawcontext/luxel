import Foundation

public enum AutomationInvocationURLBuilder {
    public static func url(for invocation: AutomationInvocation) -> URL {
        var queryItems = queryItems(for: invocation.command)
        if let success = invocation.callbacks.success {
            queryItems.append(URLQueryItem(name: "x-success", value: success.absoluteString))
        }
        if let error = invocation.callbacks.error {
            queryItems.append(URLQueryItem(name: "x-error", value: error.absoluteString))
        }

        return url(action: action(for: invocation.command), queryItems: queryItems)
    }

    private static func action(for command: AutomationCommand) -> String {
        switch command {
        case .record:
            "record"
        case .stop:
            "stop"
        case .toggle:
            "toggle"
        case .screenshot:
            "screenshot"
        case .clip:
            "clip"
        case .preferences:
            "preferences"
        case .latest:
            "latest"
        }
    }

    private static func queryItems(for command: AutomationCommand) -> [URLQueryItem] {
        switch command {
        case .record(let options):
            recordingQueryItems(for: options)
        case .stop:
            []
        case .toggle(let options):
            options.map(recordingQueryItems(for:)) ?? []
        case .screenshot(let options):
            screenshotQueryItems(for: options)
        case .clip(let seconds):
            seconds.map { [URLQueryItem(name: "seconds", value: String($0))] } ?? []
        case .preferences(let pane):
            pane.map { [URLQueryItem(name: "pane", value: $0.rawValue)] } ?? []
        case .latest(let reveal):
            reveal ? [URLQueryItem(name: "reveal", value: "true")] : []
        }
    }

    private static func recordingQueryItems(for options: AutomationRecordingOptions) -> [URLQueryItem] {
        var items = captureTargetQueryItems(for: options.target)
        if let presetName = options.presetName {
            items.append(URLQueryItem(name: "preset", value: presetName))
        }
        if let countdownSeconds = options.countdownSeconds {
            items.append(URLQueryItem(name: "countdown", value: String(countdownSeconds)))
        }
        if let outputDirectory = options.outputDirectory {
            items.append(URLQueryItem(name: "saveTo", value: outputDirectory.path))
        }
        return items
    }

    private static func screenshotQueryItems(for options: AutomationScreenshotOptions) -> [URLQueryItem] {
        var items = captureTargetQueryItems(for: options.target)
        if let format = options.format {
            items.append(URLQueryItem(name: "format", value: format.rawValue))
        }
        return items
    }

    private static func captureTargetQueryItems(for target: AutomationCaptureTarget) -> [URLQueryItem] {
        switch target {
        case .display(let display):
            [
                URLQueryItem(name: "target", value: "display"),
                URLQueryItem(name: "display", value: display.queryValue)
            ]
        case .activeWindow:
            [URLQueryItem(name: "target", value: "activeWindow")]
        case .lastArea:
            [URLQueryItem(name: "target", value: "lastArea")]
        }
    }

    private static func url(action: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "luxel"
        components.host = action
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            preconditionFailure("Automation command produced an invalid URL")
        }

        return url
    }
}

private extension AutomationDisplayTarget {
    var queryValue: String {
        switch self {
        case .main:
            "main"
        case .id(let id):
            id
        }
    }
}
