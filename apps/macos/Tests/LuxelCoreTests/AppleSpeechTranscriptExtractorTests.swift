import Foundation
import LuxelCore
import Speech
import Testing

@Suite("Apple Speech transcript extractor")
struct AppleSpeechTranscriptExtractorTests {
    @Test("extractor requires Speech authorization before reading audio")
    func extractorRequiresSpeechAuthorization() async throws {
        let extractor = AppleSpeechTranscriptExtractor(
            speechAuthorizationStatus: { .denied }
        )

        await #expect(throws: AppleSpeechTranscriptError.authorizationDenied) {
            _ = try await extractor.transcribe(
                TimedSpeechTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/missing-audio.m4a"),
                    locale: Locale(identifier: "en_US")
                ))
        }
    }
}
