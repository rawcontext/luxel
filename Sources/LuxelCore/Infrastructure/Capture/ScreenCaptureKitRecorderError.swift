public enum ScreenCaptureKitRecorderError: Error, Equatable {
    case alreadyRecording
    case alreadyPaused
    case notRecording
    case notPaused
    case startFailed(String)
    case pauseFailed(String)
    case resumeFailed(String)
    case stopFailed(String)
}
