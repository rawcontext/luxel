import Foundation
import ScreenCaptureKit
import Testing

@testable import LuxelCore

@Suite("ScreenCaptureKit audio-only recorder")
struct ScreenCaptureKitAudioOnlyRecorderTests {
    @Test("stream configuration maps system and microphone audio")
    func streamConfigurationMapsSystemAndMicrophoneAudio() throws {
        let request = try AudioRecordingRequest(
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.m4a"),
            audio: .systemAndMicrophone(deviceID: "mic-1"),
            format: .aac
        )

        let configuration = ScreenCaptureKitAudioOnlyRecorder.makeStreamConfiguration(for: request)

        #expect(configuration.width == 2)
        #expect(configuration.height == 2)
        expectStandardAudioConfiguration(configuration, microphoneDeviceID: "mic-1")
    }

    @Test("stream configuration supports microphone only")
    func streamConfigurationSupportsMicrophoneOnly() throws {
        let request = try AudioRecordingRequest(
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.m4a"),
            audio: .microphone(deviceID: "mic-2"),
            format: .alac
        )

        let configuration = ScreenCaptureKitAudioOnlyRecorder.makeStreamConfiguration(for: request)

        #expect(!configuration.capturesAudio)
        #expect(configuration.captureMicrophone)
        #expect(configuration.microphoneCaptureDeviceID == "mic-2")
        #expect(!configuration.excludesCurrentProcessAudio)
    }

    @Test("stream configuration supports system audio only")
    func streamConfigurationSupportsSystemAudioOnly() throws {
        let request = try AudioRecordingRequest(
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.m4a"),
            audio: .system,
            format: .aac
        )

        let configuration = ScreenCaptureKitAudioOnlyRecorder.makeStreamConfiguration(for: request)

        #expect(configuration.capturesAudio)
        #expect(!configuration.captureMicrophone)
        #expect(configuration.microphoneCaptureDeviceID == nil)
        #expect(configuration.excludesCurrentProcessAudio)
    }

    @Test("stream outputs consume screen frames for every audio source combination")
    func streamOutputsConsumeScreenFrames() throws {
        let requestsAndOutputs: [(AudioRecordingRequest, [SCStreamOutputType])] = [
            (
                try AudioRecordingRequest(
                    outputFileURL: URL(fileURLWithPath: "/tmp/system.m4a"),
                    audio: .system
                ),
                [.screen, .audio]
            ),
            (
                try AudioRecordingRequest(
                    outputFileURL: URL(fileURLWithPath: "/tmp/microphone.m4a"),
                    audio: .microphone(deviceID: "mic-1")
                ),
                [.screen, .microphone]
            ),
            (
                try AudioRecordingRequest(
                    outputFileURL: URL(fileURLWithPath: "/tmp/combined.m4a"),
                    audio: .systemAndMicrophone(deviceID: "mic-1")
                ),
                [.screen, .audio, .microphone]
            )
        ]

        for (request, expectedOutputs) in requestsAndOutputs {
            #expect(
                ScreenCaptureKitAudioOnlyCaptureSession.streamOutputTypes(for: request)
                    == expectedOutputs
            )
        }
    }

    @Test("screen frames stop before the audio writer")
    func screenFramesStopBeforeAudioWriter() {
        #expect(!ScreenCaptureKitAudioOnlyCaptureSession.shouldForwardToWriter(.screen))
        #expect(ScreenCaptureKitAudioOnlyCaptureSession.shouldForwardToWriter(.audio))
        #expect(ScreenCaptureKitAudioOnlyCaptureSession.shouldForwardToWriter(.microphone))
    }
}
