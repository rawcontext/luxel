import AppKit
import Foundation
import Speech

public struct AppleSpeechAuthorizationService: SpeechRecognitionAuthorizationService {
    public init() {}

    public func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState {
        Self.state(from: SFSpeechRecognizer.authorizationStatus())
    }

    public func requestAuthorization() async -> SpeechRecognitionAuthorizationState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: Self.state(from: status))
                }
            }
        case .authorized:
            return .authorized
        case .denied, .restricted:
            openSpeechRecognitionSettings()
            return .denied
        @unknown default:
            openSpeechRecognitionSettings()
            return .denied
        }
    }

    private func openSpeechRecognitionSettings() {
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
