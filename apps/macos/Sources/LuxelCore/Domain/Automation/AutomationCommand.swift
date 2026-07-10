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
        case .resultFile(let url, let contentType, let removeAfterRead):
            return appendingQueryItems(
                [
                    URLQueryItem(name: "resultPath", value: url.path),
                    URLQueryItem(name: "contentType", value: contentType),
                    URLQueryItem(name: "removeAfterRead", value: removeAfterRead ? "true" : "false")
                ],
                to: callback
            )
        }
    }

    public static func errorURL(message: String, callback: URL?) -> URL? {
        guard let callback else {
            return nil
        }

        return appendingQueryItem(name: "errorMessage", value: message, to: callback)
    }

    private static func appendingQueryItem(name: String, value: String, to url: URL) -> URL {
        appendingQueryItems([URLQueryItem(name: name, value: value)], to: url)
    }

    private static func appendingQueryItems(_ items: [URLQueryItem], to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: items)
        components.queryItems = queryItems
        return components.url ?? url
    }
}

public enum AutomationCommand: Equatable, Sendable {
    case record(AutomationRecordingOptions)
    case stop
    case toggle(AutomationRecordingOptions?)
    case clip(seconds: Int?)
    case preferences(AutomationPreferencesPane?)
    case latest(reveal: Bool)
    case transcribe(AutomationTranscriptionOptions)

    public func requiresAutomationPermission(hasActiveRecording: Bool) -> Bool {
        switch self {
        case .preferences, .stop, .latest:
            false
        case .toggle:
            !hasActiveRecording
        case .record, .clip, .transcribe:
            true
        }
    }

    public func requiresStartConfirmation(hasActiveRecording: Bool) -> Bool {
        switch self {
        case .record, .clip, .transcribe:
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
        case .clip:
            "clip the replay buffer"
        case .preferences:
            "open Luxel settings"
        case .latest:
            "open the latest recording"
        case .transcribe:
            "transcribe a local media file"
        }
    }
}

public struct AutomationTranscriptionOptions: Equatable, Sendable {
    public let inputURL: URL
    public let localeIdentifier: String?
    public let outputURL: URL?
    public let semanticTurns: Bool
    public let diarize: Bool
    public let json: Bool
    public let overwrite: Bool

    public init(
        inputURL: URL,
        localeIdentifier: String? = nil,
        outputURL: URL? = nil,
        semanticTurns: Bool = false,
        diarize: Bool = false,
        json: Bool = false,
        overwrite: Bool = false
    ) {
        self.inputURL = inputURL.standardizedFileURL
        self.localeIdentifier = localeIdentifier
        self.outputURL = outputURL?.standardizedFileURL
        self.semanticTurns = semanticTurns
        self.diarize = diarize
        self.json = json
        self.overwrite = overwrite
    }
}

public struct AutomationRecordingOptions: Equatable, Sendable {
    public let target: AutomationCaptureTarget
    public let presetName: String?
    public let frameRate: AutomationRecordingFrameRate?
    public let countdownSeconds: Int?
    public let outputDirectory: URL?

    public init(
        target: AutomationCaptureTarget,
        presetName: String? = nil,
        frameRate: AutomationRecordingFrameRate? = nil,
        countdownSeconds: Int? = nil,
        outputDirectory: URL? = nil
    ) {
        self.target = target
        self.presetName = presetName
        self.frameRate = frameRate
        self.countdownSeconds = countdownSeconds
        self.outputDirectory = outputDirectory
    }
}

public enum AutomationRecordingFrameRate: Equatable, Sendable {
    case fixed(FrameRate)
    case matchDisplay
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
    case updates
    case about
}
