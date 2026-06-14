import ArgumentParser
import Foundation
import LuxelCore

public struct LuxelCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "luxel",
        abstract: "Control Luxel from the command line.",
        subcommands: [
            LuxelRecordCommand.self,
            LuxelStopCommand.self,
            LuxelToggleCommand.self,
            LuxelScreenshotCommand.self,
            LuxelClipCommand.self,
            LuxelLatestCommand.self,
            LuxelPreferencesCommand.self
        ]
    )

    public init() {}
}

public protocol LuxelURLOpener {
    func open(_ url: URL) throws
}

public struct SystemLuxelURLOpener: LuxelURLOpener {
    public init() {}

    public func open(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LuxelCLIError.openFailed(process.terminationStatus)
        }
    }
}

public enum LuxelCLIError: LocalizedError, Equatable {
    case missingTarget
    case conflictingTargets
    case invalidCountdown
    case invalidClipDuration
    case invalidCallbackURL(String)
    case callbackConflict
    case callbackListenFailed
    case invalidCallbackTimeout
    case callbackTimedOut
    case invalidCallbackRequest
    case openFailed(Int32)
    case remoteFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingTarget:
            "Choose one capture target."
        case .conflictingTargets:
            "Choose only one capture target."
        case .invalidCountdown:
            "Countdown must be between 0 and 60 seconds."
        case .invalidClipDuration:
            "Clip duration must be greater than zero seconds."
        case .invalidCallbackURL(let name):
            "\(name) must be a non-file URL."
        case .callbackConflict:
            "--wait and --json cannot be combined with explicit x-callback URLs."
        case .callbackListenFailed:
            "Failed to start the local callback listener."
        case .invalidCallbackTimeout:
            "Callback timeout must be greater than zero seconds."
        case .callbackTimedOut:
            "Timed out waiting for Luxel to call back."
        case .invalidCallbackRequest:
            "Received an invalid callback request."
        case .openFailed(let status):
            "Failed to open Luxel URL (exit status \(status))."
        case .remoteFailure(let message):
            message
        }
    }
}

public struct LuxelRecordCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Start a Luxel recording."
    )

    @OptionGroup public var target: LuxelCaptureTargetArguments

    @Option(help: "Export preset name to use for quick recording.")
    public var preset: String?

    @Option(help: "Seconds to wait before capture starts, from 0 to 60.")
    public var countdown: Int?

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            guard let resolvedTarget = try target.resolvedTarget(required: true) else {
                throw LuxelCLIError.missingTarget
            }

            return try AutomationInvocation(
                command: .record(AutomationRecordingOptions(
                    target: resolvedTarget,
                    presetName: preset,
                    countdownSeconds: validatedCountdown(countdown)
                )),
                callbacks: callbacks.resolvedCallbacks()
            )
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelStopCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the current Luxel recording."
    )

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            try AutomationInvocation(command: .stop, callbacks: callbacks.resolvedCallbacks())
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelToggleCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "toggle",
        abstract: "Stop the active recording, or start one when a target is provided."
    )

    @OptionGroup public var target: LuxelCaptureTargetArguments

    @Option(help: "Export preset name to use when starting a quick recording.")
    public var preset: String?

    @Option(help: "Seconds to wait before capture starts, from 0 to 60.")
    public var countdown: Int?

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            let resolvedTarget = try target.resolvedTarget(required: false)
            guard resolvedTarget != nil || (preset == nil && countdown == nil) else {
                throw LuxelCLIError.missingTarget
            }

            let options = try resolvedTarget.map {
                AutomationRecordingOptions(
                    target: $0,
                    presetName: preset,
                    countdownSeconds: try validatedCountdown(countdown)
                )
            }

            return try AutomationInvocation(command: .toggle(options), callbacks: callbacks.resolvedCallbacks())
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelScreenshotCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a Luxel screenshot."
    )

    @OptionGroup public var target: LuxelCaptureTargetArguments

    @Option(help: "Screenshot format: png, jpeg, or heic.")
    public var format: LuxelScreenshotFormat?

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            guard let resolvedTarget = try target.resolvedTarget(required: true) else {
                throw LuxelCLIError.missingTarget
            }

            return try AutomationInvocation(
                command: .screenshot(AutomationScreenshotOptions(
                    target: resolvedTarget,
                    format: format?.domainValue
                )),
                callbacks: callbacks.resolvedCallbacks()
            )
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelClipCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "Clip the replay buffer."
    )

    @Option(help: "Seconds of replay buffer history to clip.")
    public var seconds: Int?

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            if let seconds, seconds <= 0 {
                throw LuxelCLIError.invalidClipDuration
            }

            return try AutomationInvocation(command: .clip(seconds: seconds), callbacks: callbacks.resolvedCallbacks())
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelPreferencesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "preferences",
        abstract: "Open Luxel settings."
    )

    @Option(help: "Settings pane to open.")
    public var pane: LuxelPreferencesPane?

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            try AutomationInvocation(command: .preferences(pane?.domainValue), callbacks: callbacks.resolvedCallbacks())
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelLatestCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "latest",
        abstract: "Open the latest Luxel recording."
    )

    @Flag(help: "Reveal the latest recording in Finder instead of opening it.")
    public var reveal = false

    @OptionGroup public var callbacks: LuxelCallbackArguments

    @OptionGroup public var execution: LuxelCommandExecutionArguments

    public init() {}

    public var invocation: AutomationInvocation {
        get throws {
            try AutomationInvocation(
                command: .latest(reveal: reveal),
                callbacks: callbacks.resolvedCallbacks()
            )
        }
    }

    public mutating func run() throws {
        try runLuxelCommand(invocation, execution: execution)
    }
}

public struct LuxelCaptureTargetArguments: ParsableArguments {
    @Option(help: "Display target. Use 'main' or a display identifier.")
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
              url.scheme?.lowercased() != "file" else {
            throw LuxelCLIError.invalidCallbackURL(name)
        }

        return url
    }
}

public enum LuxelScreenshotFormat: String, CaseIterable, ExpressibleByArgument {
    case png
    case jpeg
    case heic

    var domainValue: ScreenshotFormat {
        switch self {
        case .png:
            .png
        case .jpeg:
            .jpeg
        case .heic:
            .heic
        }
    }
}

public enum LuxelPreferencesPane: String, CaseIterable, ExpressibleByArgument {
    case general
    case presets
    case shortcuts
    case screenshots
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
        case .screenshots:
            .screenshots
        case .updates:
            .updates
        case .about:
            .about
        }
    }
}

private func validatedCountdown(_ countdown: Int?) throws -> Int? {
    guard let countdown else {
        return nil
    }

    guard (0...60).contains(countdown) else {
        throw LuxelCLIError.invalidCountdown
    }

    return countdown
}
