import AppKit
import Foundation
import Speech

public struct AppleSpeechAuthorizationService: SpeechRecognitionAuthorizationService {
    public init() {}

    public func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState {
        Self.state(from: SFSpeechRecognizer.authorizationStatus())
    }

    public func requestAuthorization() async -> SpeechRecognitionAuthorizationState {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            // Fire-and-forget so authorization UI is never blocked by a caller.
            Task { @MainActor in
                guard
                    let url = URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                    )
                else {
                    return
                }

                NSWorkspace.shared.open(url)
            }
        }

        return Self.state(from: status)
    }

    private static func state(
        from status: SFSpeechRecognizerAuthorizationStatus
    ) -> SpeechRecognitionAuthorizationState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }
}
