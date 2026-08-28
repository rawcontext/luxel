import Foundation

public enum CommandLineAutomationProtocol {
    public static let version = 1

    public static let capabilities = CommandLineAutomationCommand.allCases.map(\.rawValue)
}

public struct CommandLineAutomationRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let command: CommandLineAutomationCommand
    public let arguments: CommandLineAutomationArguments
    public let output: CommandLineAutomationOutputOptions

    public init(
        protocolVersion: Int = CommandLineAutomationProtocol.version,
        requestID: UUID,
        command: CommandLineAutomationCommand,
        arguments: CommandLineAutomationArguments = CommandLineAutomationArguments(),
        output: CommandLineAutomationOutputOptions = CommandLineAutomationOutputOptions()
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.command = command
        self.arguments = arguments
        self.output = output
    }

    public func validate() throws {
        guard protocolVersion == CommandLineAutomationProtocol.version else {
            throw CommandLineAutomationValidationError.unsupportedProtocolVersion(protocolVersion)
        }

        try require(arguments.hasExpectedPayload(for: command))

        try arguments.validate(for: command)
    }

    private func require(_ condition: Bool) throws {
        guard condition else {
            throw CommandLineAutomationValidationError.unexpectedArguments(command)
        }
    }
}

public enum CommandLineAutomationCommand: String, CaseIterable, Codable, Equatable, Hashable,
    Sendable {
    case record
    case stop
    case toggle
    case clip
    case latest
    case preferences
    case editor
    case convert
    case export
    case transcribe
    case accessAdd
    case accessCheck
    case accessList
    case accessRevoke
    case doctor
    case cancel
}

public struct CommandLineAutomationArguments: Codable, Equatable, Sendable {
    public let recording: CommandLineRecordingArguments?
    public let clip: CommandLineClipArguments?
    public let latest: CommandLineLatestArguments?
    public let preferences: CommandLinePreferencesArguments?
    public let editor: CommandLineEditorArguments?
    public let convert: CommandLineConvertArguments?
    public let export: CommandLineExportArguments?
    public let transcribe: CommandLineTranscribeArguments?
    public let access: CommandLineAccessArguments?
    public let cancel: CommandLineCancelArguments?

    public init(
        recording: CommandLineRecordingArguments? = nil,
        clip: CommandLineClipArguments? = nil,
        latest: CommandLineLatestArguments? = nil,
        preferences: CommandLinePreferencesArguments? = nil,
        editor: CommandLineEditorArguments? = nil,
        convert: CommandLineConvertArguments? = nil,
        export: CommandLineExportArguments? = nil,
        transcribe: CommandLineTranscribeArguments? = nil,
        access: CommandLineAccessArguments? = nil,
        cancel: CommandLineCancelArguments? = nil
    ) {
        self.recording = recording
        self.clip = clip
        self.latest = latest
        self.preferences = preferences
        self.editor = editor
        self.convert = convert
        self.export = export
        self.transcribe = transcribe
        self.access = access
        self.cancel = cancel
    }

    fileprivate var isEmpty: Bool {
        payloadCount == 0
    }

    fileprivate var onlyContainsRecording: Bool {
        payloadCount == (recording == nil ? 0 : 1)
    }

    fileprivate func hasExpectedPayload(for command: CommandLineAutomationCommand) -> Bool {
        let expectations: [CommandLineAutomationCommand: Bool] = [
            .record: recording != nil,
            .stop: isEmpty,
            .toggle: onlyContainsRecording,
            .clip: clip != nil,
            .latest: latest != nil,
            .preferences: preferences != nil,
            .editor: editor != nil,
            .convert: convert != nil,
            .export: export != nil,
            .transcribe: transcribe != nil,
            .accessAdd: access != nil,
            .accessCheck: access != nil,
            .accessList: isEmpty,
            .accessRevoke: access != nil,
            .doctor: isEmpty,
            .cancel: cancel != nil
        ]
        return expectations[command] == true
    }

    private var payloadCount: Int {
        [
            recording != nil,
            clip != nil,
            latest != nil,
            preferences != nil,
            editor != nil,
            convert != nil,
            export != nil,
            transcribe != nil,
            access != nil,
            cancel != nil
        ].count(where: { $0 })
    }

    fileprivate func validate(for command: CommandLineAutomationCommand) throws {
        guard payloadCount <= 1 else {
            throw CommandLineAutomationValidationError.unexpectedArguments(command)
        }

        try recording?.validate()
        try validateClip()
        try convert?.validate()
        try validateEditor()
        try validateExport()
        try validateTranscription()
        try validateAccess(for: command)
    }

    private func validateClip() throws {
        guard let seconds = clip?.seconds, seconds <= 0 else {
            return
        }
        throw CommandLineAutomationValidationError.invalidValue("seconds")
    }

    private func validateEditor() throws {
        guard editor?.inputPath.isEmpty == true else {
            return
        }
        throw CommandLineAutomationValidationError.invalidValue("inputPath")
    }

    private func validateExport() throws {
        guard let export, export.requestPath.isEmpty || export.outputPath.isEmpty else {
            return
        }
        throw CommandLineAutomationValidationError.invalidValue("exportPath")
    }

    private func validateTranscription() throws {
        guard transcribe?.inputPath.isEmpty == true else {
            return
        }
        throw CommandLineAutomationValidationError.invalidValue("inputPath")
    }

    private func validateAccess(for command: CommandLineAutomationCommand) throws {
        guard let access else {
            return
        }
        switch command {
        case .accessAdd, .accessCheck:
            guard access.path?.isEmpty == false, access.grantID == nil else {
                throw CommandLineAutomationValidationError.invalidValue("path")
            }
        case .accessRevoke:
            guard access.grantID != nil, access.path == nil else {
                throw CommandLineAutomationValidationError.invalidValue("grantID")
            }
        default:
            throw CommandLineAutomationValidationError.unexpectedArguments(command)
        }
    }
}

public struct CommandLineRecordingArguments: Codable, Equatable, Sendable {
    public let target: CommandLineCaptureTarget
    public let displayID: String?
    public let preset: String?
    public let framesPerSecond: Int?
    public let matchesDisplayFrameRate: Bool
    public let countdownSeconds: Int?
    public let outputDirectoryPath: String?

    public init(
        target: CommandLineCaptureTarget,
        displayID: String? = nil,
        preset: String? = nil,
        framesPerSecond: Int? = nil,
        matchesDisplayFrameRate: Bool = false,
        countdownSeconds: Int? = nil,
        outputDirectoryPath: String? = nil
    ) {
        self.target = target
        self.displayID = displayID
        self.preset = preset
        self.framesPerSecond = framesPerSecond
        self.matchesDisplayFrameRate = matchesDisplayFrameRate
        self.countdownSeconds = countdownSeconds
        self.outputDirectoryPath = outputDirectoryPath
    }

    fileprivate func validate() throws {
        if target == .display, displayID?.isEmpty != false {
            throw CommandLineAutomationValidationError.invalidValue("displayID")
        }
        if target != .display, displayID != nil {
            throw CommandLineAutomationValidationError.invalidValue("displayID")
        }
        if let framesPerSecond,
            !AppSettings.recordingFrameRateRange.contains(framesPerSecond) {
            throw CommandLineAutomationValidationError.invalidValue("framesPerSecond")
        }
        if framesPerSecond != nil, matchesDisplayFrameRate {
            throw CommandLineAutomationValidationError.invalidValue("framesPerSecond")
        }
        if let countdownSeconds, !(0...60).contains(countdownSeconds) {
            throw CommandLineAutomationValidationError.invalidValue("countdownSeconds")
        }
    }
}

public enum CommandLineCaptureTarget: String, Codable, Equatable, Sendable {
    case display
    case activeWindow
    case lastArea
}

public struct CommandLineClipArguments: Codable, Equatable, Sendable {
    public let seconds: Int?

    public init(seconds: Int? = nil) {
        self.seconds = seconds
    }
}

public struct CommandLineLatestArguments: Codable, Equatable, Sendable {
    public let reveal: Bool

    public init(reveal: Bool = false) {
        self.reveal = reveal
    }
}

public struct CommandLinePreferencesArguments: Codable, Equatable, Sendable {
    public let pane: String?

    public init(pane: String? = nil) {
        self.pane = pane
    }
}

public struct CommandLineEditorArguments: Codable, Equatable, Sendable {
    public let inputPath: String

    public init(inputPath: String) {
        self.inputPath = inputPath
    }
}

public struct CommandLineConvertArguments: Codable, Equatable, Sendable {
    public let inputPath: String
    public let outputPath: String
    public let format: String?
    public let width: Int?
    public let height: Int?
    public let framesPerSecond: Int?
    public let startSeconds: Double?
    public let endSeconds: Double?
    public let durationSeconds: Double?
    public let speed: Double
    public let mute: Bool
    public let cropToFill: Bool
    public let crop: CommandLineCropRect?
    public let quality: String?
    public let overwrite: Bool

    public init(
        inputPath: String,
        outputPath: String,
        format: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        framesPerSecond: Int? = nil,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        speed: Double = 1,
        mute: Bool = false,
        cropToFill: Bool = false,
        crop: CommandLineCropRect? = nil,
        quality: String? = nil,
        overwrite: Bool = false
    ) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.format = format
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.durationSeconds = durationSeconds
        self.speed = speed
        self.mute = mute
        self.cropToFill = cropToFill
        self.crop = crop
        self.quality = quality
        self.overwrite = overwrite
    }

    fileprivate func validate() throws {
        guard !inputPath.isEmpty, !outputPath.isEmpty else {
            throw CommandLineAutomationValidationError.invalidValue("path")
        }
        guard (width == nil) == (height == nil) else {
            throw CommandLineAutomationValidationError.invalidValue("size")
        }
        if let width, width <= 0 {
            throw CommandLineAutomationValidationError.invalidValue("width")
        }
        if let height, height <= 0 {
            throw CommandLineAutomationValidationError.invalidValue("height")
        }
        if let framesPerSecond, framesPerSecond <= 0 {
            throw CommandLineAutomationValidationError.invalidValue("framesPerSecond")
        }
        if endSeconds != nil, durationSeconds != nil {
            throw CommandLineAutomationValidationError.invalidValue("trim")
        }
        let values = [startSeconds, endSeconds, durationSeconds, speed]
        guard values.allSatisfy({ $0?.isFinite != false }), speed > 0 else {
            throw CommandLineAutomationValidationError.invalidValue("time")
        }
    }
}

public struct CommandLineCropRect: Codable, Equatable, Sendable {
    public let originX: Int
    public let originY: Int
    public let width: Int
    public let height: Int

    public init(originX: Int, originY: Int, width: Int, height: Int) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
    }
}
