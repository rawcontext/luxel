import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func executeCommandLineRequest(
        _ request: CommandLineAutomationRequest,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws -> CommandLineAutomationResult {
        switch request.command {
        case .record, .stop, .toggle, .clip, .latest:
            return try await executeCommandLineCaptureRequest(
                request,
                openSettings: openSettings,
                openRecording: openRecording
            )
        case .preferences, .editor:
            return try await executeCommandLinePresentationRequest(
                request,
                openSettings: openSettings,
                openRecording: openRecording
            )
        case .convert, .export, .transcribe:
            return try await executeCommandLineMediaRequest(request)
        case .accessAdd, .accessCheck, .accessList, .accessRevoke, .doctor, .cancel:
            return try executeCommandLineManagementRequest(request)
        }
    }

    private func executeCommandLineCaptureRequest(
        _ request: CommandLineAutomationRequest,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws -> CommandLineAutomationResult {
        let command: AutomationCommand
        switch request.command {
        case .record:
            guard let arguments = request.arguments.recording else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            command = .record(try automationRecordingOptions(arguments))
        case .stop:
            command = .stop
        case .toggle:
            let options = try request.arguments.recording.map(automationRecordingOptions)
            command = .toggle(options)
        case .clip:
            command = .clip(seconds: request.arguments.clip?.seconds)
        case .latest:
            command = .latest(reveal: request.arguments.latest?.reveal ?? false)
        default:
            throw LuxelCommandLineAutomationError.commandUnavailable(request.command.rawValue)
        }
        return try await commandLineAutomationResult(
            executeAutomationCommand(
                command,
                openSettings: openSettings,
                openRecording: openRecording
            )
        )
    }

    private func executeCommandLinePresentationRequest(
        _ request: CommandLineAutomationRequest,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws -> CommandLineAutomationResult {
        switch request.command {
        case .preferences:
            openSettings()
            return CommandLineAutomationResult()
        case .editor:
            guard let inputPath = request.arguments.editor?.inputPath else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
            return try await withCommandLineFileAccess(paths: [inputURL]) {
                openRecording(inputURL)
                return CommandLineAutomationResult(filePath: inputURL.path)
            }
        default:
            throw LuxelCommandLineAutomationError.commandUnavailable(request.command.rawValue)
        }
    }

    private func executeCommandLineMediaRequest(
        _ request: CommandLineAutomationRequest
    ) async throws -> CommandLineAutomationResult {
        switch request.command {
        case .convert:
            guard let arguments = request.arguments.convert else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            return try await runCommandLineConversion(arguments)
        case .export:
            guard let arguments = request.arguments.export else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            return try await runCommandLineExport(arguments)
        case .transcribe:
            guard let arguments = request.arguments.transcribe else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            return try await runCommandLineTranscription(arguments)
        default:
            throw LuxelCommandLineAutomationError.commandUnavailable(request.command.rawValue)
        }
    }

    private func executeCommandLineManagementRequest(
        _ request: CommandLineAutomationRequest
    ) throws -> CommandLineAutomationResult {
        switch request.command {
        case .accessAdd:
            return try addCommandLineAccess(suggestedPath: request.arguments.access?.path)
        case .accessCheck:
            guard let path = request.arguments.access?.path else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            return CommandLineAutomationResult(
                grant: try commandLineAccess(for: URL(fileURLWithPath: path)).summary)
        case .accessList:
            return CommandLineAutomationResult(grants: commandLineAccessSummaries())
        case .accessRevoke:
            guard let id = request.arguments.access?.grantID else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            removeCommandLineFolderGrant(id)
            return CommandLineAutomationResult()
        case .doctor:
            return CommandLineAutomationResult(doctor: commandLineDoctorReport())
        case .cancel:
            guard let jobID = request.arguments.cancel?.jobID else {
                throw LuxelCommandLineAutomationError.missingArguments
            }
            commandLineJobs[jobID]?.cancel()
            return CommandLineAutomationResult()
        default:
            throw LuxelCommandLineAutomationError.commandUnavailable(request.command.rawValue)
        }
    }

    private func automationRecordingOptions(
        _ arguments: CommandLineRecordingArguments
    ) throws -> AutomationRecordingOptions {
        let outputDirectory = arguments.outputDirectoryPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if let outputDirectory {
            _ = try commandLineAccess(for: outputDirectory)
        }
        let target: AutomationCaptureTarget =
            switch arguments.target {
            case .display:
                if arguments.displayID == "main" {
                    .display(.main)
                } else {
                    .display(.id(arguments.displayID ?? ""))
                }
            case .activeWindow: .activeWindow
            case .lastArea: .lastArea
            }
        let frameRate: AutomationRecordingFrameRate?
        if arguments.matchesDisplayFrameRate {
            frameRate = .matchDisplay
        } else if let framesPerSecond = arguments.framesPerSecond {
            frameRate = .fixed(try FrameRate(framesPerSecond))
        } else {
            frameRate = nil
        }
        return AutomationRecordingOptions(
            target: target,
            presetName: arguments.preset,
            frameRate: frameRate,
            countdownSeconds: arguments.countdownSeconds,
            outputDirectory: outputDirectory
        )
    }

    private func commandLineAutomationResult(
        _ result: AutomationExecutionResult
    ) throws -> CommandLineAutomationResult {
        switch result {
        case .accepted:
            return CommandLineAutomationResult()
        case .recording(let id):
            return CommandLineAutomationResult(recordingID: id)
        case .file(let url):
            return CommandLineAutomationResult(filePath: url.path)
        case .resultFile(let url, let contentType, let removeAfterRead):
            defer { if removeAfterRead { try? FileManager.default.removeItem(at: url) } }
            let data = try Data(contentsOf: url)
            return CommandLineAutomationResult(
                text: String(data: data, encoding: .utf8),
                contentType: contentType
            )
        }
    }

    private func runCommandLineTranscription(
        _ arguments: CommandLineTranscribeArguments
    ) async throws -> CommandLineAutomationResult {
        let input = URL(fileURLWithPath: arguments.inputPath).standardizedFileURL
        let output = arguments.outputPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        return try await withCommandLineFileAccess(paths: [input] + [output].compactMap { $0 }) {
            let result = try await self.runAutomationTranscription(
                AutomationTranscriptionOptions(
                    inputURL: input,
                    localeIdentifier: arguments.locale,
                    outputURL: output,
                    semanticTurns: arguments.semanticTurns,
                    diarize: arguments.diarize,
                    json: arguments.format == .json,
                    overwrite: arguments.overwrite
                )
            )
            return try self.commandLineAutomationResult(result)
        }
    }
}
