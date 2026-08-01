import ScreenCaptureKit
import Testing

func expectStandardAudioConfiguration(
    _ configuration: SCStreamConfiguration,
    microphoneDeviceID: String
) {
    #expect(configuration.capturesAudio)
    #expect(configuration.captureMicrophone)
    #expect(configuration.microphoneCaptureDeviceID == microphoneDeviceID)
    #expect(configuration.excludesCurrentProcessAudio)
    #expect(configuration.sampleRate == 48_000)
    #expect(configuration.channelCount == 2)
    #expect(configuration.queueDepth == 8)
}
