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
        #expect(configuration.capturesAudio)
        #expect(configuration.captureMicrophone)
        #expect(configuration.microphoneCaptureDeviceID == "mic-1")
        #expect(configuration.excludesCurrentProcessAudio)
        #expect(configuration.sampleRate == 48_000)
        #expect(configuration.channelCount == 2)
        #expect(configuration.queueDepth == 8)
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
}
