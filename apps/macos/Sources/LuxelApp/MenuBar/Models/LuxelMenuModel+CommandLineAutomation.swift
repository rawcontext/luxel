import AppKit
import Foundation
import LuxelCore

private enum LuxelCommandLineAutomationError: LocalizedError {
    case controlDisabled
    case pairingDenied
    case folderSelectionCanceled
    case unknownClient
    case invalidAuthentication
    case expiredRequest
    case replayedRequest
    case requestDigestMismatch
    case requestIDMismatch
    case fileAccessRequired(String)
    case fileAccessRevoked(String)
    case missingArguments
    case commandUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .controlDisabled:
            "Command-line control is disabled in Luxel Settings."
        case .pairingDenied:
            "Pairing was denied in Luxel."
        case .folderSelectionCanceled:
            "No folder was selected."
        case .unknownClient:
            "This command-line client is not paired with Luxel. Run `luxel pair`."
        case .invalidAuthentication:
            "The command-line request could not be authenticated. Run `luxel pair` again."
        case .expiredRequest:
            "The command-line request expired before Luxel received it."
        case .replayedRequest:
            "Luxel rejected a repeated command-line request."
        case .requestDigestMismatch:
            "The command-line request body did not match its signed digest."
        case .requestIDMismatch:
            "The command-line request identifier did not match its callback."
        case .fileAccessRequired(let path):
            "Luxel does not have access to \(path). Run `luxel access add \"\(path)\"`."
        case .fileAccessRevoked(let path):
            "Luxel's folder access was revoked for \(path). Add the folder again."
        case .missingArguments:
            "The command-line request is missing required arguments."
        case .commandUnavailable(let command):
            "The \(command) command is not available in this version of Luxel."
        }
    }

    var code: String {
        switch self {
        case .controlDisabled: "control_disabled"
        case .pairingDenied: "pairing_denied"
        case .folderSelectionCanceled: "folder_selection_canceled"
        case .unknownClient: "not_paired"
        case .invalidAuthentication: "authentication_failed"
        case .expiredRequest: "request_expired"
        case .replayedRequest: "request_replayed"
        case .requestDigestMismatch: "digest_mismatch"
        case .requestIDMismatch: "request_id_mismatch"
        case .fileAccessRequired: "file_access_required"
        case .fileAccessRevoked: "file_access_revoked"
        case .missingArguments: "invalid_request"
        case .commandUnavailable: "command_unavailable"
        }
    }
}

@MainActor
extension LuxelMenuModel {
    func handleCommandLineAutomationURL(
        _ url: URL,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws {
        let scheme = AutomationURLScheme.registered(in: Bundle.main.infoDictionary)
        let invocation = try CommandLineAutomationBootstrapParser.parse(
            url,
            expectedScheme: scheme
        )
        switch invocation.action {
        case .pair:
            do {
                try await pairCommandLineClient(invocation)
            } catch {
                try? await postCommandLineError(error, sequence: 0, invocation: invocation)
                throw error
            }
        case .run:
            try await runCommandLineRequest(
                invocation,
                openSettings: openSettings,
                openRecording: openRecording
            )
        }
    }

    private func pairCommandLineClient(
        _ invocation: CommandLineAutomationBootstrapInvocation
    ) async throws {
        guard let clientName = invocation.clientName else {
            throw LuxelCommandLineAutomationError.missingArguments
        }
        guard approveCommandLinePairing(clientName: clientName) else {
            throw LuxelCommandLineAutomationError.pairingDenied
        }

        let credentialStore = CommandLineCredentialStore()
        let clientID = UUID()
        let secret = try credentialStore.makeSecret()
        try credentialStore.saveSecret(secret, clientID: clientID)
        let replacedClientIDs = settings.commandLinePairedClients
            .filter { $0.name == clientName }
            .map(\.id)

        let credential = CommandLinePairingCredential(
            clientID: clientID,
            secret: secret.base64EncodedString(),
            appVersion: appMetadata.version
        )
        do {
            try await CommandLineLoopbackClient().post(
                CommandLineAutomationEvent(
                    requestID: invocation.requestID,
                    sequence: 0,
                    kind: .result,
                    result: CommandLineAutomationResult(pairing: credential)
                ),
                to: invocation.endpoint
            )
        } catch {
            credentialStore.removeSecret(clientID: clientID)
            throw error
        }

        replacedClientIDs.forEach(credentialStore.removeSecret)
        settings.commandLinePairedClients.removeAll { $0.name == clientName }
        settings.commandLinePairedClients.append(
            CommandLinePairedClient(id: clientID, name: clientName)
        )
        settings.commandLineControlEnabled = true
        saveSettings()
    }

    private func approveCommandLinePairing(clientName: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = LuxelLocalization.string(
            "commandLine.pair.title",
            defaultValue: "Allow Command Line Control?"
        )
        alert.informativeText = LuxelLocalization.format(
            "commandLine.pair.message",
            defaultValue: "%@ wants to control Luxel. Approve only if you started `luxel pair` in Terminal.",
            clientName
        )
        alert.addButton(withTitle: LuxelLocalization.string(
            "commandLine.pair.allow",
            defaultValue: "Allow"
        ))
        alert.addButton(withTitle: LuxelLocalization.string(
            "commandLine.pair.deny",
            defaultValue: "Deny"
        ))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runCommandLineRequest(
        _ invocation: CommandLineAutomationBootstrapInvocation,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws {
        guard let clientID = invocation.clientID,
              settings.commandLinePairedClients.contains(where: { $0.id == clientID })
        else {
            throw LuxelCommandLineAutomationError.unknownClient
        }
        guard let secret = CommandLineCredentialStore().secret(clientID: clientID),
              CommandLineAutomationAuthentication.authenticate(invocation, secret: secret)
        else {
            throw LuxelCommandLineAutomationError.invalidAuthentication
        }

        let request: CommandLineAutomationRequest
        do {
            guard settings.commandLineControlEnabled else {
                throw LuxelCommandLineAutomationError.controlDisabled
            }
            try validateCommandLineFreshness(invocation, clientID: clientID)
            let requestData = try await CommandLineLoopbackClient().fetchRequest(
                from: invocation.endpoint
            )
            guard CommandLineAutomationAuthentication.digest(requestData) == invocation.requestDigest else {
                throw LuxelCommandLineAutomationError.requestDigestMismatch
            }
            request = try JSONDecoder().decode(CommandLineAutomationRequest.self, from: requestData)
            try request.validate()
            guard request.requestID == invocation.requestID else {
                throw LuxelCommandLineAutomationError.requestIDMismatch
            }
        } catch {
            try? await postCommandLineError(error, sequence: 0, invocation: invocation)
            throw error
        }
        markCommandLineClientUsed(clientID)

        try await postCommandLineEvent(
            CommandLineAutomationEvent(
                requestID: request.requestID,
                sequence: 0,
                kind: .accepted,
                jobID: request.requestID
            ),
            invocation: invocation
        )
        let job = Task { @MainActor in
            try await self.executeCommandLineRequest(
                request,
                openSettings: openSettings,
                openRecording: openRecording
            )
        }
        commandLineJobs[request.requestID] = job
        defer { commandLineJobs[request.requestID] = nil }

        do {
            let result = try await job.value
            try await postCommandLineEvent(
                CommandLineAutomationEvent(
                    requestID: request.requestID,
                    sequence: 1,
                    kind: .result,
                    jobID: request.requestID,
                    result: result
                ),
                invocation: invocation
            )
        } catch is CancellationError {
            try await postCommandLineEvent(
                CommandLineAutomationEvent(
                    requestID: request.requestID,
                    sequence: 1,
                    kind: .canceled,
                    jobID: request.requestID
                ),
                invocation: invocation
            )
        } catch {
            try? await postCommandLineError(error, sequence: 1, invocation: invocation)
            throw error
        }
    }

    private func validateCommandLineFreshness(
        _ invocation: CommandLineAutomationBootstrapInvocation,
        clientID: UUID
    ) throws {
        guard let timestamp = invocation.timestamp,
              abs(Date().timeIntervalSince1970 - Double(timestamp)) <= 300
        else {
            throw LuxelCommandLineAutomationError.expiredRequest
        }
        let cutoff = Date().addingTimeInterval(-600)
        commandLineNonces = commandLineNonces.filter { $0.value > cutoff }
        let client = clientID.uuidString.lowercased()
        let nonceKey = "nonce:\(client):\(invocation.nonce ?? "")"
        let requestKey = "request:\(client):\(invocation.requestID.uuidString.lowercased())"
        guard commandLineNonces[nonceKey] == nil,
              commandLineNonces[requestKey] == nil
        else {
            throw LuxelCommandLineAutomationError.replayedRequest
        }
        commandLineNonces[nonceKey] = Date()
        commandLineNonces[requestKey] = Date()
    }

    private func markCommandLineClientUsed(_ clientID: UUID) {
        guard let index = settings.commandLinePairedClients.firstIndex(where: { $0.id == clientID }) else {
            return
        }
        settings.commandLinePairedClients[index].lastUsedAt = Date()
        saveSettings()
    }

    private func executeCommandLineRequest(
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
            return CommandLineAutomationResult(grant: try commandLineAccess(for: URL(fileURLWithPath: path)).summary)
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
        let target: AutomationCaptureTarget = switch arguments.target {
        case .display:
            if arguments.displayID == "main" { .display(.main) } else { .display(.id(arguments.displayID ?? "")) }
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

    private func addCommandLineAccess(suggestedPath: String?) throws -> CommandLineAutomationResult {
        let suggested = suggestedPath.map(URL.init(fileURLWithPath:)) ?? settings.recordingsDirectory
        guard let directory = try bookmarkedDirectoryPicker.chooseDirectory(currentDirectory: suggested) else {
            throw LuxelCommandLineAutomationError.folderSelectionCanceled
        }
        if let existing = settings.commandLineFolderGrants.first(where: {
            $0.directory.url.standardizedFileURL == directory.url.standardizedFileURL
        }) {
            return CommandLineAutomationResult(grant: commandLineGrantSummary(existing))
        }
        let grant = CommandLineFolderGrant(directory: directory)
        settings.commandLineFolderGrants.append(grant)
        saveSettings()
        return CommandLineAutomationResult(grant: commandLineGrantSummary(grant))
    }

    private func commandLineDoctorReport() -> CommandLineDoctorReport {
        CommandLineDoctorReport(
            appVersion: appMetadata.version,
            appBuild: appMetadata.build,
            commandLineControlEnabled: settings.commandLineControlEnabled,
            recordingsDirectoryPath: settings.recordingsDirectory.path,
            screenRecordingStatus: commandLinePermissionName(screenRecordingStatus),
            microphoneStatus: commandLinePermissionName(microphoneStatus),
            cameraStatus: commandLinePermissionName(cameraStatus)
        )
    }

    private func commandLinePermissionName(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .unknown: "unknown"
        }
    }

    private func commandLineAccessSummaries() -> [CommandLineFolderGrantSummary] {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        var summaries = [CommandLineFolderGrantSummary(
            id: stableCommandLineGrantID("movies"),
            path: movies.path,
            source: .movies,
            status: .resolved
        )]
        summaries.append(CommandLineFolderGrantSummary(
            id: stableCommandLineGrantID("recordings"),
            path: settings.recordingsDirectory.path,
            source: .recordings,
            status: settings.recordingsDirectoryBookmark?.accessState ?? .resolved
        ))
        summaries.append(contentsOf: settings.commandLineFolderGrants.map(commandLineGrantSummary))
        return summaries
    }

    private func commandLineGrantSummary(_ grant: CommandLineFolderGrant) -> CommandLineFolderGrantSummary {
        CommandLineFolderGrantSummary(
            id: grant.id,
            path: grant.directory.url.path,
            source: .additional,
            status: grant.directory.accessState
        )
    }

    private func stableCommandLineGrantID(_ value: String) -> UUID {
        let hex = CommandLineAutomationAuthentication.digest(Data(value.utf8))
        let uuid = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-8\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuid)!
    }

    private struct ResolvedCommandLineAccess {
        let summary: CommandLineFolderGrantSummary
        let bookmark: BookmarkedDirectory?
    }

    private func commandLineAccess(for url: URL) throws -> ResolvedCommandLineAccess {
        let target = canonicalCommandLineURL(url)
        if path(target, isInside: settings.recordingsDirectory) {
            return ResolvedCommandLineAccess(
                summary: commandLineAccessSummaries()[1],
                bookmark: settings.recordingsDirectoryBookmark
            )
        }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        if path(target, isInside: movies) {
            return ResolvedCommandLineAccess(summary: commandLineAccessSummaries()[0], bookmark: nil)
        }
        for grant in settings.commandLineFolderGrants where path(target, isInside: grant.directory.url) {
            return ResolvedCommandLineAccess(
                summary: commandLineGrantSummary(grant),
                bookmark: grant.directory
            )
        }
        throw LuxelCommandLineAutomationError.fileAccessRequired(target.path)
    }

    private func path(_ target: URL, isInside directory: URL) -> Bool {
        let targetPath = canonicalCommandLineURL(target).path
        let rootPath = canonicalCommandLineURL(directory).path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    private func canonicalCommandLineURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath()
        }
        return standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appending(path: standardized.lastPathComponent)
    }

    func withCommandLineFileAccess<Result: Sendable>(
        paths: [URL],
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        var bookmarks: [BookmarkedDirectory] = []
        for path in paths {
            if let bookmark = try commandLineAccess(for: path).bookmark,
               !bookmarks.contains(where: { $0.url == bookmark.url }) {
                bookmarks.append(bookmark)
            }
        }
        return try await withCommandLineBookmarks(bookmarks, index: 0, operation: operation)
    }

    private func withCommandLineBookmarks<Result: Sendable>(
        _ bookmarks: [BookmarkedDirectory],
        index: Int,
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        guard index < bookmarks.count else { return try await operation() }
        let bookmark = bookmarks[index]
        let result = try await directoryAccessService.withAccess(to: bookmark) { _ in
            try await withCommandLineBookmarks(bookmarks, index: index + 1, operation: operation)
        }
        guard let value = result.value else {
            throw LuxelCommandLineAutomationError.fileAccessRevoked(bookmark.url.path)
        }
        return value
    }

    private func postCommandLineEvent(
        _ event: CommandLineAutomationEvent,
        invocation: CommandLineAutomationBootstrapInvocation
    ) async throws {
        try await CommandLineLoopbackClient().post(event, to: invocation.endpoint)
    }

    private func postCommandLineError(
        _ error: Error,
        sequence: Int,
        invocation: CommandLineAutomationBootstrapInvocation
    ) async throws {
        let automationError = error as? LuxelCommandLineAutomationError
        let payload = CommandLineAutomationErrorPayload(
            code: automationError?.code ?? "command_failed",
            message: error.localizedDescription
        )
        try await postCommandLineEvent(
            CommandLineAutomationEvent(
                requestID: invocation.requestID,
                sequence: sequence,
                kind: .error,
                error: payload
            ),
            invocation: invocation
        )
    }
}
