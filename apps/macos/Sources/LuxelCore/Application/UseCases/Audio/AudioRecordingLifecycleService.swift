import Foundation

public final class AudioRecordingLifecycleService: Sendable {
    private let recorder: any AudioRecorder
    private let history: RecordingHistoryService
    private let outputFinalizer: any RecordingOutputFinalizer
    private let outputState = AudioRecordingLifecycleOutputState()

    public init(
        recorder: any AudioRecorder,
        history: RecordingHistoryService,
        outputFinalizer: any RecordingOutputFinalizer = PassthroughRecordingOutputFinalizer()
    ) {
        self.recorder = recorder
        self.history = history
        self.outputFinalizer = outputFinalizer
    }

    @discardableResult
    public func startRecording(
        _ request: AudioRecordingRequest,
        name: String? = nil,
        outputPlan: RecordingOutputFinalizationPlan? = nil
    ) async throws -> ActiveRecording {
        let outputPlan = outputPlan ?? .direct(request.outputFileURL)
        await outputState.set(outputPlan)

        let activeRecording = history.setCurrentRecording(
            fileURL: outputPlan.stagingFileURL,
            name: name,
            options: request.recordingOptions
        )
        let recorderRequest = try request.replacingOutputFileURL(outputPlan.stagingFileURL)

        do {
            try await recorder.startRecording(recorderRequest)
            return activeRecording.replacingFileURL(outputPlan.finalFileURL)
        } catch {
            await outputState.clear()
            history.clearCurrentRecording()
            throw error
        }
    }

    @discardableResult
    public func stopRecording(recordingName: String? = nil) async throws -> PastRecording {
        try await recorder.stopRecording()
        let finalizationResult: RecordingOutputFinalizationResult?
        do {
            finalizationResult = try await finalizeCurrentOutput()
        } catch {
            history.clearCurrentRecording()
            await outputState.clear()
            throw RecordingLifecycleError.outputFinalizationFailed(error.recordingLifecycleDescription)
        }

        guard
            let recording = history.stopCurrentRecording(
                finalFileURL: finalizationResult?.fileURL,
                recordingName: recordingName
            )
        else {
            await outputState.clear()
            throw RecordingLifecycleError.noActiveRecording
        }

        await outputState.clear()
        return recording
    }

    private func finalizeCurrentOutput() async throws -> RecordingOutputFinalizationResult? {
        guard let outputPlan = await outputState.plan else {
            return nil
        }

        return try await Task.detached(priority: .userInitiated) { [outputFinalizer] in
            try outputFinalizer.finalize(outputPlan)
        }.value
    }
}

extension Error {
    fileprivate var recordingLifecycleDescription: String {
        if let errorDescription = (self as? LocalizedError)?.errorDescription, !errorDescription.isEmpty {
            return errorDescription
        }

        let localizedDescription = (self as NSError).localizedDescription
        return localizedDescription.isEmpty ? String(describing: self) : localizedDescription
    }
}

private actor AudioRecordingLifecycleOutputState {
    private(set) var plan: RecordingOutputFinalizationPlan?

    func set(_ plan: RecordingOutputFinalizationPlan) {
        self.plan = plan
    }

    func clear() {
        plan = nil
    }
}
