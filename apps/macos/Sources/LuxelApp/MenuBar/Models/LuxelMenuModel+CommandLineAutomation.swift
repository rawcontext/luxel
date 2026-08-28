import AppKit
import Foundation
import LuxelCore

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
            defaultValue:
                "%@ wants to control Luxel. Approve only if you started `luxel pair` in Terminal.",
            clientName
        )
        alert.addButton(
            withTitle: LuxelLocalization.string(
                "commandLine.pair.allow",
                defaultValue: "Allow"
            ))
        alert.addButton(
            withTitle: LuxelLocalization.string(
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

        let request = try await validatedCommandLineRequest(
            invocation, clientID: clientID)
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
        try await executeCommandLineJob(
            request,
            invocation: invocation,
            openSettings: openSettings,
            openRecording: openRecording
        )
    }

    private func validatedCommandLineRequest(
        _ invocation: CommandLineAutomationBootstrapInvocation,
        clientID: UUID
    ) async throws -> CommandLineAutomationRequest {
        do {
            guard settings.commandLineControlEnabled else {
                throw LuxelCommandLineAutomationError.controlDisabled
            }
            try validateCommandLineFreshness(invocation, clientID: clientID)
            let requestData = try await CommandLineLoopbackClient().fetchRequest(
                from: invocation.endpoint
            )
            guard CommandLineAutomationAuthentication.digest(requestData) == invocation.requestDigest
            else {
                throw LuxelCommandLineAutomationError.requestDigestMismatch
            }
            let request = try JSONDecoder().decode(
                CommandLineAutomationRequest.self, from: requestData)
            try request.validate()
            guard request.requestID == invocation.requestID else {
                throw LuxelCommandLineAutomationError.requestIDMismatch
            }
            return request
        } catch {
            try? await postCommandLineError(error, sequence: 0, invocation: invocation)
            throw error
        }
    }

    private func executeCommandLineJob(
        _ request: CommandLineAutomationRequest,
        invocation: CommandLineAutomationBootstrapInvocation,
        openSettings: @escaping @MainActor () -> Void,
        openRecording: @escaping @MainActor (URL) -> Void
    ) async throws {
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
        guard let index = settings.commandLinePairedClients.firstIndex(where: { $0.id == clientID })
        else {
            return
        }
        settings.commandLinePairedClients[index].lastUsedAt = Date()
        saveSettings()
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
