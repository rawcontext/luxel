import Foundation
import Speech

public struct AppleSpeechRecognitionAuthorizationService: SpeechRecognitionAuthorizationService {
    public init() {}

    public func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState {
        Self.state(from: SFSpeechRecognizer.authorizationStatus())
    }

    public func requestAuthorization() async -> SpeechRecognitionAuthorizationState {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else {
            return Self.state(from: status)
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.state(from: status))
            }
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
