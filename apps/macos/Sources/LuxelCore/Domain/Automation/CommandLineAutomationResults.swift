import Foundation

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
