@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import Testing
import os

@testable import LuxelCore

@Suite("Recording audio level sampler")
struct RecordingAudioLevelSamplerTests {
    @Test("system and microphone PCM levels publish and combine")
    func audioLevelsPublishAndCombine() throws {
        var mixer = RecordingAudioLevelMixer(audio: .systemAndMicrophone(deviceID: nil))
        let samples = OSAllocatedUnfairLock(initialState: [AudioLevelSample]())
        let handler: @Sendable (AudioLevelSample) -> Void = { sample in
            samples.withLock { $0.append(sample) }
        }

        mixer.publish(try audioSample(level: 0.3), outputType: .audio, to: handler)
        mixer.publish(try audioSample(level: 0.4), outputType: .microphone, to: handler)

        let published = samples.withLock { $0 }
        #expect(published.count == 2)
        #expect(abs(published[0].rms - 0.3) < 0.0001)
        #expect(abs(published[0].peak - 0.3) < 0.0001)
        #expect(abs(published[1].rms - 0.5) < 0.0001)
        #expect(abs(published[1].peak - 0.7) < 0.0001)
    }

    @Test("screen frames and non-audio formats do not publish levels")
    func videoSamplesDoNotPublish() throws {
        var mixer = RecordingAudioLevelMixer(audio: .systemAndMicrophone(deviceID: nil))
        let samples = OSAllocatedUnfairLock(initialState: [AudioLevelSample]())
        let handler: @Sendable (AudioLevelSample) -> Void = { sample in
            samples.withLock { $0.append(sample) }
        }
        let video = try videoSample()

        mixer.publish(video, outputType: .screen, to: handler)
        mixer.publish(video, outputType: .audio, to: handler)

        #expect(CMSampleBufferAudioLevelSampler.sample(from: video) == nil)
        #expect(samples.withLock { $0.isEmpty })
    }

    @Test("audio levels without a listener do not enter the mix")
    func audioWithoutListenerIsIgnored() throws {
        var mixer = RecordingAudioLevelMixer(audio: .systemAndMicrophone(deviceID: nil))
        mixer.publish(try audioSample(level: 0.6), outputType: .audio, to: nil)

        let microphone = AudioLevelSample(rms: 0.4, peak: 0.4)
        #expect(mixer.update(microphone, outputType: .microphone) == microphone)
    }

    private func audioSample(level: Float) throws -> CMSampleBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16
        let channels = try #require(buffer.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<16 {
                channels[channel][frame] = level
            }
        }
        var description: CMAudioFormatDescription?
        #expect(
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: format.streamDescription,
                layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                extensions: nil, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(
            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                makeDataReadyCallback: nil, refcon: nil, formatDescription: try #require(description),
                sampleCount: 16, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        let result = try #require(sample)
        #expect(
            CMSampleBufferSetDataBufferFromAudioBufferList(
                result, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                bufferList: buffer.audioBufferList) == noErr)
        return result
    }

    private func videoSample() throws -> CMSampleBuffer {
        var description: CMVideoFormatDescription?
        #expect(
            CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
                width: 64, height: 64, extensions: nil, formatDescriptionOut: &description) == noErr)
        var sample: CMSampleBuffer?
        #expect(
            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
                makeDataReadyCallback: nil, refcon: nil, formatDescription: try #require(description),
                sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
