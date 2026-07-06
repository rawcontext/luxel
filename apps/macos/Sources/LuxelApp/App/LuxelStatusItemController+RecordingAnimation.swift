import AppKit
import LuxelCore

extension LuxelStatusItemController {
    func startRecordingAnimation() {
        guard recordingAnimationTimer == nil else {
            return
        }

        recordingFrameIndex = 0
        recordingLevelHistory = []
        setRecordingFrame()

        let timer = Timer(timeInterval: 1.0 / 18.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceRecordingFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingAnimationTimer = timer
    }

    func stopRecordingAnimation() {
        recordingAnimationTimer?.invalidate()
        recordingAnimationTimer = nil
        recordingFrameIndex = 0
        recordingLevelHistory = []
    }

    private func advanceRecordingFrame() {
        recordingFrameIndex = (recordingFrameIndex + 1) % 18
        setRecordingFrame()
    }

    private func setRecordingFrame() {
        let presentation = model.recordingPresentation()
        let sample = model.audioLevelSample
        recordingLevelHistory.append(min(1, max(CGFloat(sample.rms), CGFloat(sample.peak))))
        if recordingLevelHistory.count > Self.waveformBarCount {
            recordingLevelHistory.removeFirst(recordingLevelHistory.count - Self.waveformBarCount)
        }

        let frame = makeActiveRecordingFrame(
            elapsedText: presentation.menuBarTitle,
            levelHistory: recordingLevelHistory
        )
        setButtonImage(
            frame,
            key: "recording-\(recordingFrameIndex)-\(presentation.menuBarTitle)-\(sample)"
        )
    }

    func setButtonImage(_ image: NSImage?, key: String) {
        guard currentImageKey != key else {
            return
        }

        statusItem.button?.image = image
        currentImageKey = key
    }
}
