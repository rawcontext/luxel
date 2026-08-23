import Foundation
import LuxelCore
import Testing

@Suite("Voice detection settings")
struct VoiceDetectionSettingsTests {
    @Test("speech detection prompts default off and decode explicit opt-in")
    func defaultsOffAndDecodesExplicitOptIn() throws {
        let missingData = Data(
            """
            {
                "recordingsDirectory": "file:///Users/example/Movies/Luxel/"
            }
            """.utf8
        )
        let enabledData = Data(
            """
            {
                "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
                "speechDetectionPromptsEnabled": true,
                "speechDetectionDisclosureAccepted": true
            }
            """.utf8
        )

        let missing = try JSONDecoder().decode(AppSettings.self, from: missingData)
        let enabled = try JSONDecoder().decode(AppSettings.self, from: enabledData)

        #expect(!missing.speechDetectionPromptsEnabled)
        #expect(!missing.speechDetectionDisclosureAccepted)
        #expect(enabled.speechDetectionPromptsEnabled)
        #expect(enabled.speechDetectionDisclosureAccepted)
    }

    @Test("speech detection prompt settings round-trip")
    func settingsRoundTrip() throws {
        let settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            speechDetectionPromptsEnabled: true,
            speechDetectionDisclosureAccepted: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.speechDetectionPromptsEnabled)
        #expect(decoded.speechDetectionDisclosureAccepted)
    }
}
