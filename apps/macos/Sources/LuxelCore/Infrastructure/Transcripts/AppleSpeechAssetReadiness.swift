import Foundation

enum AppleSpeechAssetStatus: Equatable, Sendable {
    case installed
    case supported
    case downloading
    case unsupported
}

struct AppleSpeechAssetReadinessWaiter: Sendable {
    let retryInterval: Duration
    let maximumTransientAttempts: Int
    let maximumDownloadPolls: Int

    init(
        retryInterval: Duration = .milliseconds(500),
        maximumTransientAttempts: Int = 20,
        maximumDownloadPolls: Int = 1_200
    ) {
        self.retryInterval = retryInterval
        self.maximumTransientAttempts = maximumTransientAttempts
        self.maximumDownloadPolls = maximumDownloadPolls
    }

    func waitUntilReady(
        installed: @escaping @Sendable () async -> Bool = { false },
        status: @escaping @Sendable () async -> AppleSpeechAssetStatus,
        install: @escaping @Sendable () async throws -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) async throws {
        var transientAttempts = 0
        var downloadPolls = 0

        while true {
            try Task.checkCancellation()

            switch await currentStatus(installed: installed, status: status) {
            case .installed:
                return
            case .supported:
                transientAttempts += 1
                guard transientAttempts < maximumTransientAttempts else {
                    throw AppleSpeechTranscriptError.assetsUnavailable
                }

                do {
                    try await install()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try await sleep(retryInterval)
                    continue
                }

                try await sleep(retryInterval)
            case .downloading:
                transientAttempts = 0
                downloadPolls += 1
                guard downloadPolls < maximumDownloadPolls else {
                    throw AppleSpeechTranscriptError.assetsUnavailable
                }
                try await sleep(retryInterval)
            case .unsupported:
                transientAttempts += 1
                guard transientAttempts < maximumTransientAttempts else {
                    throw AppleSpeechTranscriptError.assetsUnavailable
                }
                try await sleep(retryInterval)
            }
        }
    }

    private func currentStatus(
        installed: @escaping @Sendable () async -> Bool,
        status: @escaping @Sendable () async -> AppleSpeechAssetStatus
    ) async -> AppleSpeechAssetStatus {
        if await installed() {
            return .installed
        }
        return await status()
    }
}

actor AppleSpeechAssetReadinessGate {
    private var inFlight: [String: Task<Void, Error>] = [:]

    func wait(
        for localeIdentifier: String,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let task = inFlight[localeIdentifier] {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            return
        }

        let task = Task<Void, Error> {
            try await operation()
        }
        inFlight[localeIdentifier] = task

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            inFlight[localeIdentifier] = nil
        } catch {
            inFlight[localeIdentifier] = nil
            throw error
        }
    }
}
