import LuxelCore

@MainActor
extension LuxelMenuModel {
    func startSpeechPromptAudioOnlyRecording() async {
        guard canBeginRecordingStart else {
            return
        }

        do {
            await startPreparedAudioOnlyRecording(
                try makeSpeechPromptAudioRecordingRequest(),
                noticeMessage: nil,
                notchRecordingActionID: nil
            )
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func startPreparedAudioOnlyRecording(
        _ request: AudioRecordingRequest,
        noticeMessage: String?,
        notchRecordingActionID: NotchActivityActionID?
    ) async {
        recordingNoticeMessage = noticeMessage
        recordingActionErrorMessage = nil
        activeNotchRecordingActionID = notchRecordingActionID
        recordingState = .starting

        do {
            if request.captureKeystrokes {
                await keystrokeLivePreviewPanelController.prepareForCapture(
                    isEnabled: settings.keystrokeLivePreviewEnabled
                )
            }

            let recordingName = request.outputFileURL.deletingPathExtension().lastPathComponent
            let outputPlan = try recordingOutputFinalizationPlan(for: request.outputFileURL)
            let activeRecording = try await audioRecordingLifecycleService.startRecording(
                request,
                name: recordingName,
                outputPlan: outputPlan
            )
            recordingState = .recording(
                activeRecording,
                RecordingMenuClock(startedAt: activeRecording.date)
            )
            if request.captureKeystrokes {
                keystrokeRecordingSession.start()
            }
        } catch {
            keystrokeRecordingSession.cancel()
            await keystrokeLivePreviewPanelController.close()
            recordingState = .failed(errorMessage(error))
        }
    }
}
