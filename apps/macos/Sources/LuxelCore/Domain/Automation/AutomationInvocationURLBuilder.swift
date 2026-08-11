import Foundation

public enum AutomationInvocationURLBuilder {
    public static func url(
        for invocation: AutomationInvocation,
        scheme: String = AutomationURLScheme.production
    ) -> URL {
        var queryItems = queryItems(for: invocation.command)
        if let success = invocation.callbacks.success {
            queryItems.append(URLQueryItem(name: "x-success", value: success.absoluteString))
        }
        if let error = invocation.callbacks.error {
            queryItems.append(URLQueryItem(name: "x-error", value: error.absoluteString))
        }

        return url(action: action(for: invocation.command), queryItems: queryItems, scheme: scheme)
    }

    private static func action(for command: AutomationCommand) -> String {
        switch command {
        case .record:
            "record"
        case .stop:
            "stop"
        case .toggle:
            "toggle"
        case .clip:
            "clip"
        case .preferences:
            "preferences"
        case .latest:
            "latest"
        case .transcribe:
            "transcribe"
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
        case .clip(let seconds):
            seconds.map { [URLQueryItem(name: "seconds", value: String($0))] } ?? []
        case .preferences(let pane):
            pane.map { [URLQueryItem(name: "pane", value: $0.rawValue)] } ?? []
        case .latest(let reveal):
            reveal ? [URLQueryItem(name: "reveal", value: "true")] : []
        case .transcribe(let options):
            transcriptionQueryItems(for: options)
        }
    }

    private static func transcriptionQueryItems(
        for options: AutomationTranscriptionOptions
    ) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "input", value: options.inputURL.path)]
        if let localeIdentifier = options.localeIdentifier {
            items.append(URLQueryItem(name: "locale", value: localeIdentifier))
        }
        if let outputURL = options.outputURL {
            items.append(URLQueryItem(name: "output", value: outputURL.path))
        }
        if options.semanticTurns {
            items.append(URLQueryItem(name: "semanticTurns", value: "true"))
        }
        if options.diarize {
            items.append(URLQueryItem(name: "diarize", value: "true"))
        }
        if options.json {
            items.append(URLQueryItem(name: "json", value: "true"))
        }
        if options.overwrite {
            items.append(URLQueryItem(name: "overwrite", value: "true"))
        }
        return items
    }

    private static func recordingQueryItems(for options: AutomationRecordingOptions) -> [URLQueryItem] {
        var items = captureTargetQueryItems(for: options.target)
        if let presetName = options.presetName {
            items.append(URLQueryItem(name: "preset", value: presetName))
        }
        if let frameRate = options.frameRate {
            items.append(URLQueryItem(name: "fps", value: frameRate.queryValue))
        }
        if let countdownSeconds = options.countdownSeconds {
            items.append(URLQueryItem(name: "countdown", value: String(countdownSeconds)))
        }
        if let outputDirectory = options.outputDirectory {
            items.append(URLQueryItem(name: "saveTo", value: outputDirectory.path))
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

    private static func url(
        action: String,
        queryItems: [URLQueryItem],
        scheme: String
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = action
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            preconditionFailure("Automation command produced an invalid URL")
        }

        return url
    }
}

extension AutomationRecordingFrameRate {
    fileprivate var queryValue: String {
        switch self {
        case .fixed(let frameRate):
            String(frameRate.framesPerSecond)
        case .matchDisplay:
            "display"
        }
    }
}

extension AutomationDisplayTarget {
    fileprivate var queryValue: String {
        switch self {
        case .main:
            "main"
        case .id(let id):
            id
        }
    }
}
