import Foundation

@MainActor
extension LuxelMenuModel {
    func pauseRecording() async {
        guard case .recording(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .pausing(activeRecording, clock)

        do {
            try await recordingLifecycleService.pauseRecording()
            keystrokeRecordingSession.recordingDidPause()
            recordingState = .paused(activeRecording, clock.paused(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .recording(activeRecording, clock)
        }
    }

    func resumeRecording() async {
        guard case .paused(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .resuming(activeRecording, clock)

        do {
            try await recordingLifecycleService.resumeRecording()
            keystrokeRecordingSession.recordingDidResume()
            recordingState = .recording(activeRecording, clock.resumed(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .paused(activeRecording, clock)
        }
    }
}
