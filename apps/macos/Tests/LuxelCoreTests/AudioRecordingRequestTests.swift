import Foundation
import LuxelCore
import Testing

@Suite("Audio recording request")
struct AudioRecordingRequestTests {
    @Test("request rejects missing audio source")
    func requestRejectsMissingAudioSource() {
        #expect(throws: AudioRecordingRequestError.missingAudioSource) {
            _ = try AudioRecordingRequest(
                outputFileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
                audio: .none
            )
        }
    }

    @Test("request derives audio-only recording options")
    func requestDerivesAudioOnlyRecordingOptions() throws {
        let request = try AudioRecordingRequest(
            outputFileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            audio: .microphone(deviceID: "mic-1"),
            format: .alac
        )

        #expect(request.format == .alac)
        #expect(request.format.fileExtension == "m4a")
        #expect(request.recordingOptions.isAudioOnly)
        #expect(request.recordingOptions.frameRate == 0)
        #expect(request.recordingOptions.audio == .microphone(deviceID: "mic-1"))
    }

    @Test("formats expose settings labels and file extensions")
    func formatsExposeSettingsLabelsAndFileExtensions() {
        #expect(AudioRecordingFormat.aac.label == "AAC")
        #expect(AudioRecordingFormat.alac.label == "ALAC")
        #expect(AudioRecordingFormat.allCases.map(\.fileExtension) == ["m4a", "m4a"])
    }
}
