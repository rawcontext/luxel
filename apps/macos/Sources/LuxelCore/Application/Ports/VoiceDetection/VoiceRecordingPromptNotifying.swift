public protocol VoiceRecordingPromptNotifying: Sendable {
    func authorizationStatus() async -> VoiceDetectionAuthorizationStatus
    func requestAuthorization() async -> VoiceDetectionAuthorizationStatus
    @MainActor func openSettings()
    func postPrompt() async throws
    func removePrompt() async
}
