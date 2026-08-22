public protocol VoiceRecordingPromptNotifying: Sendable {
    func authorizationStatus() async -> VoiceDetectionAuthorizationStatus
    func requestAuthorization() async -> VoiceDetectionAuthorizationStatus
    func postPrompt() async throws
    func removePrompt() async
}
