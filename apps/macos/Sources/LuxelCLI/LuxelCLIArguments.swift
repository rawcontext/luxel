import ArgumentParser
import Foundation
import LuxelCore

public struct LuxelCaptureTargetArguments: ParsableArguments {
    @Option(
        help: "Display target. Use 'main' or a display identifier.",
        completion: .list(["main"])
    )
    public var display: String?

    @Flag(
        name: [.customLong("active-window"), .customLong("window-active")],
        help: "Use the active window target."
    )
    public var activeWindow = false

    @Flag(help: "Use the last selected area target.")
    public var lastArea = false

    public init() {}

    public func resolvedTarget(required: Bool) throws -> AutomationCaptureTarget? {
        let selectedTargets = [
            display.map { _ in () },
            activeWindow ? () : nil,
            lastArea ? () : nil
        ].compactMap(\.self).count

        if selectedTargets > 1 {
            throw LuxelCLIError.conflictingTargets
        }

        if let display {
            return .display(display.lowercased() == "main" ? .main : .id(display))
        }

        if activeWindow {
            return .activeWindow
        }

        if lastArea {
            return .lastArea
        }

        if required {
            throw LuxelCLIError.missingTarget
        }

        return nil
    }
}

public struct LuxelCallbackArguments: ParsableArguments {
    @Option(name: .customLong("x-success"), help: "Callback URL for successful execution.")
    public var successCallback: String?

    @Option(name: .customLong("x-error"), help: "Callback URL for failed execution.")
    public var errorCallback: String?

    public init() {}

    public func resolvedCallbacks() throws -> AutomationCallbacks {
        try AutomationCallbacks(
            success: callbackURL(successCallback, name: "x-success"),
            error: callbackURL(errorCallback, name: "x-error")
        )
    }

    private func callbackURL(_ value: String?, name: String) throws -> URL? {
        guard let value else {
            return nil
        }

        guard let url = URL(string: value),
              url.scheme?.isEmpty == false,
              !url.isFileURL,
              url.scheme?.lowercased() != "file"
        else {
            throw LuxelCLIError.invalidCallbackURL(name)
        }

        return url
    }
}

public enum LuxelPreferencesPane: String, CaseIterable, ExpressibleByArgument {
    case general
    case presets
    case shortcuts
    case updates
    case about

    var domainValue: AutomationPreferencesPane {
        switch self {
        case .general:
            .general
        case .presets:
            .presets
        case .shortcuts:
            .shortcuts
        case .updates:
            .updates
        case .about:
            .about
        }
    }
}

func validatedCountdown(_ countdown: Int?) throws -> Int? {
    guard let countdown else {
        return nil
    }

    guard (0...60).contains(countdown) else {
        throw LuxelCLIError.invalidCountdown
    }

    return countdown
}

func validatedRecordingFrameRate(
    _ value: String?
) throws -> AutomationRecordingFrameRate? {
    guard let value else {
        return nil
    }

    if value.lowercased() == "display" {
        return .matchDisplay
    }

    guard let framesPerSecond = Int(value),
          let frameRate = try? AppSettings.makeRecordingFrameRate(framesPerSecond)
    else {
        throw LuxelCLIError.invalidRecordingFrameRate
    }

    return .fixed(frameRate)
}

func resolvedOutputDirectory(_ path: String?) throws -> URL? {
    guard let path else {
        return nil
    }

    if let url = URL(string: path),
       url.scheme != nil {
        guard url.isFileURL, !url.path.isEmpty else {
            throw LuxelCLIError.invalidOutputDirectory
        }

        return url.standardizedFileURL
    }

    let expandedPath = (path as NSString).expandingTildeInPath
    guard !expandedPath.isEmpty else {
        throw LuxelCLIError.invalidOutputDirectory
    }

    return URL(fileURLWithPath: expandedPath).standardizedFileURL
}
