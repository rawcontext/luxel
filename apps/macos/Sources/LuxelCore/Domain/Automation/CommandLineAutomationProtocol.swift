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

        switch command {
        case .record:
            try require(arguments.recording != nil)
        case .toggle:
            try require(arguments.onlyContainsRecording)
        case .clip:
            try require(arguments.clip != nil)
        case .latest:
            try require(arguments.latest != nil)
        case .preferences:
            try require(arguments.preferences != nil)
        case .editor:
            try require(arguments.editor != nil)
        case .convert:
            try require(arguments.convert != nil)
        case .export:
            try require(arguments.export != nil)
        case .transcribe:
            try require(arguments.transcribe != nil)
        case .accessAdd, .accessCheck, .accessRevoke:
            try require(arguments.access != nil)
        case .cancel:
            try require(arguments.cancel != nil)
        case .stop, .accessList, .doctor:
            try require(arguments.isEmpty)
        }

        try arguments.validate(for: command)
    }

    private func require(_ condition: Bool) throws {
        guard condition else {
            throw CommandLineAutomationValidationError.unexpectedArguments(command)
        }
    }
}

public enum CommandLineAutomationCommand: String, CaseIterable, Codable, Equatable, Sendable {
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

        if let recording {
            try recording.validate()
        }
        if let clip, let seconds = clip.seconds, seconds <= 0 {
            throw CommandLineAutomationValidationError.invalidValue("seconds")
        }
        if let convert {
            try convert.validate()
        }
        if let editor, editor.inputPath.isEmpty {
            throw CommandLineAutomationValidationError.invalidValue("inputPath")
        }
        if let export, export.requestPath.isEmpty || export.outputPath.isEmpty {
            throw CommandLineAutomationValidationError.invalidValue("exportPath")
        }
        if let transcribe, transcribe.inputPath.isEmpty {
            throw CommandLineAutomationValidationError.invalidValue("inputPath")
        }
        if let access {
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
            !AppSettings.recordingFrameRateRange.contains(framesPerSecond)
        {
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

public struct CommandLineExportArguments: Codable, Equatable, Sendable {
    public let requestPath: String
    public let outputPath: String
    public let overwrite: Bool

    public init(requestPath: String, outputPath: String, overwrite: Bool = false) {
        self.requestPath = requestPath
        self.outputPath = outputPath
        self.overwrite = overwrite
    }
}

public struct CommandLineTranscribeArguments: Codable, Equatable, Sendable {
    public let inputPath: String
    public let locale: String?
    public let outputPath: String?
    public let semanticTurns: Bool
    public let diarize: Bool
    public let format: CommandLineTranscriptFormat
    public let overwrite: Bool

    public init(
        inputPath: String,
        locale: String? = nil,
        outputPath: String? = nil,
        semanticTurns: Bool = false,
        diarize: Bool = false,
        format: CommandLineTranscriptFormat = .text,
        overwrite: Bool = false
    ) {
        self.inputPath = inputPath
        self.locale = locale
        self.outputPath = outputPath
        self.semanticTurns = semanticTurns
        self.diarize = diarize
        self.format = format
        self.overwrite = overwrite
    }
}

public enum CommandLineTranscriptFormat: String, Codable, Equatable, Sendable {
    case text
    case json
}

public struct CommandLineAccessArguments: Codable, Equatable, Sendable {
    public let path: String?
    public let grantID: UUID?

    public init(path: String? = nil, grantID: UUID? = nil) {
        self.path = path
        self.grantID = grantID
    }
}

public struct CommandLineCancelArguments: Codable, Equatable, Sendable {
    public let jobID: UUID

    public init(jobID: UUID) {
        self.jobID = jobID
    }
}

public struct CommandLineAutomationOutputOptions: Codable, Equatable, Sendable {
    public let json: Bool
    public let progress: Bool
    public let quiet: Bool

    public init(json: Bool = false, progress: Bool = false, quiet: Bool = false) {
        self.json = json
        self.progress = progress
        self.quiet = quiet
    }
}

public enum CommandLineAutomationEventKind: String, Codable, Equatable, Sendable {
    case accepted
    case progress
    case result
    case error
    case canceled
}

public struct CommandLineAutomationEvent: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let sequence: Int
    public let kind: CommandLineAutomationEventKind
    public let jobID: UUID?
    public let progress: CommandLineAutomationProgress?
    public let result: CommandLineAutomationResult?
    public let error: CommandLineAutomationErrorPayload?

    public init(
        protocolVersion: Int = CommandLineAutomationProtocol.version,
        requestID: UUID,
        sequence: Int,
        kind: CommandLineAutomationEventKind,
        jobID: UUID? = nil,
        progress: CommandLineAutomationProgress? = nil,
        result: CommandLineAutomationResult? = nil,
        error: CommandLineAutomationErrorPayload? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.sequence = sequence
        self.kind = kind
        self.jobID = jobID
        self.progress = progress
        self.result = result
        self.error = error
    }
}

public struct CommandLineAutomationProgress: Codable, Equatable, Sendable {
    public let phase: String
    public let fraction: Double?
    public let message: String?

    public init(phase: String, fraction: Double? = nil, message: String? = nil) {
        self.phase = phase
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.message = message
    }
}

public struct CommandLineAutomationResult: Codable, Equatable, Sendable {
    public let filePath: String?
    public let recordingID: String?
    public let text: String?
    public let contentType: String?
    public let export: CommandLineExportResult?
    public let doctor: CommandLineDoctorReport?
    public let grants: [CommandLineFolderGrantSummary]?
    public let grant: CommandLineFolderGrantSummary?
    public let pairing: CommandLinePairingCredential?

    public init(
        filePath: String? = nil,
        recordingID: String? = nil,
        text: String? = nil,
        contentType: String? = nil,
        export: CommandLineExportResult? = nil,
        doctor: CommandLineDoctorReport? = nil,
        grants: [CommandLineFolderGrantSummary]? = nil,
        grant: CommandLineFolderGrantSummary? = nil,
        pairing: CommandLinePairingCredential? = nil
    ) {
        self.filePath = filePath
        self.recordingID = recordingID
        self.text = text
        self.contentType = contentType
        self.export = export
        self.doctor = doctor
        self.grants = grants
        self.grant = grant
        self.pairing = pairing
    }
}

public struct CommandLineExportResult: Codable, Equatable, Sendable {
    public let filePath: String
    public let format: String
    public let width: Int
    public let height: Int
    public let shouldMute: Bool
    public let fileSizeBytes: Int64?

    public init(
        filePath: String,
        format: String,
        width: Int,
        height: Int,
        shouldMute: Bool,
        fileSizeBytes: Int64? = nil
    ) {
        self.filePath = filePath
        self.format = format
        self.width = width
        self.height = height
        self.shouldMute = shouldMute
        self.fileSizeBytes = fileSizeBytes
    }
}

public struct CommandLineDoctorReport: Codable, Equatable, Sendable {
    public let appVersion: String
    public let appBuild: String
    public let minimumProtocolVersion: Int
    public let maximumProtocolVersion: Int
    public let capabilities: [String]
    public let commandLineControlEnabled: Bool
    public let recordingsDirectoryPath: String
    public let screenRecordingStatus: String
    public let microphoneStatus: String
    public let cameraStatus: String

    public init(
        appVersion: String,
        appBuild: String,
        minimumProtocolVersion: Int = CommandLineAutomationProtocol.version,
        maximumProtocolVersion: Int = CommandLineAutomationProtocol.version,
        capabilities: [String] = CommandLineAutomationProtocol.capabilities,
        commandLineControlEnabled: Bool,
        recordingsDirectoryPath: String,
        screenRecordingStatus: String,
        microphoneStatus: String,
        cameraStatus: String
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.minimumProtocolVersion = minimumProtocolVersion
        self.maximumProtocolVersion = maximumProtocolVersion
        self.capabilities = capabilities
        self.commandLineControlEnabled = commandLineControlEnabled
        self.recordingsDirectoryPath = recordingsDirectoryPath
        self.screenRecordingStatus = screenRecordingStatus
        self.microphoneStatus = microphoneStatus
        self.cameraStatus = cameraStatus
    }
}

public struct CommandLineFolderGrantSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let source: CommandLineFolderGrantSource
    public let status: BookmarkedDirectoryAccessState

    public init(
        id: UUID,
        path: String,
        source: CommandLineFolderGrantSource,
        status: BookmarkedDirectoryAccessState
    ) {
        self.id = id
        self.path = path
        self.source = source
        self.status = status
    }
}

public enum CommandLineFolderGrantSource: String, Codable, Equatable, Sendable {
    case movies
    case recordings
    case additional
}

public struct CommandLinePairingCredential: Codable, Equatable, Sendable {
    public let clientID: UUID
    public let secret: String
    public let appVersion: String
    public let protocolVersion: Int

    public init(
        clientID: UUID,
        secret: String,
        appVersion: String,
        protocolVersion: Int = CommandLineAutomationProtocol.version
    ) {
        self.clientID = clientID
        self.secret = secret
        self.appVersion = appVersion
        self.protocolVersion = protocolVersion
    }
}

public struct CommandLineAutomationErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let recoveryCommand: String?

    public init(code: String, message: String, recoveryCommand: String? = nil) {
        self.code = code
        self.message = message
        self.recoveryCommand = recoveryCommand
    }
}

public enum CommandLineAutomationValidationError: Error, Equatable, Sendable {
    case unsupportedProtocolVersion(Int)
    case unexpectedArguments(CommandLineAutomationCommand)
    case invalidValue(String)
}
