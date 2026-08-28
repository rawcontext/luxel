import Foundation

public final class AudioRecordingLifecycleService: Sendable {
    private let recorder: any AudioRecorder
    private let history: RecordingHistoryService
    private let outputFinalizer: any RecordingOutputFinalizer
    private let terminationProtection: any RecordingTerminationProtection
    private let outputState = AudioRecordingLifecycleOutputState()

    public init(
        recorder: any AudioRecorder,
        history: RecordingHistoryService,
        outputFinalizer: any RecordingOutputFinalizer = PassthroughRecordingOutputFinalizer(),
        terminationProtection: any RecordingTerminationProtection =
            NoopRecordingTerminationProtection()
    ) {
        self.recorder = recorder
        self.history = history
        self.outputFinalizer = outputFinalizer
        self.terminationProtection = terminationProtection
    }

    @discardableResult
    public func startRecording(
        _ request: AudioRecordingRequest,
        name: String? = nil,
        outputPlan: RecordingOutputFinalizationPlan? = nil
    ) async throws -> ActiveRecording {
        let outputPlan = outputPlan ?? .direct(request.outputFileURL)
        await outputState.set(outputPlan)
        terminationProtection.recordingWillStart()

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
            terminationProtection.recordingDidEnd()
            throw error
        }
    }

    @discardableResult
    public func stopRecording(recordingName: String? = nil) async throws -> PastRecording {
        try await recorder.stopRecording()
        let finalizationResult: RecordingOutputFinalizationResult?
        do {
            finalizationResult = try await finalizeRecordingOutput(
                await outputState.plan,
                using: outputFinalizer
            )
        } catch {
            history.clearCurrentRecording()
            await outputState.clear()
            terminationProtection.recordingDidEnd()
            throw RecordingLifecycleError.outputFinalizationFailed(error.preferredLocalizedDescription)
        }

        guard
            let recording = history.stopCurrentRecording(
                finalFileURL: finalizationResult?.fileURL,
                recordingName: recordingName
            )
        else {
            await outputState.clear()
            terminationProtection.recordingDidEnd()
            throw RecordingLifecycleError.noActiveRecording
        }

        await outputState.clear()
        terminationProtection.recordingDidEnd()
        return recording
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
