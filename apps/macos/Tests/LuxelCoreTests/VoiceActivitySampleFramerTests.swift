import AVFoundation
import Testing

@testable import LuxelCore

struct VoiceActivitySampleFramerTests {
    @Test("framer emits ordered exact model frames and retains only a remainder")
    func exactFramesAndRemainder() {
        var framer = VoiceActivitySampleFramer()
        let samples = (0..<(VoiceActivitySampleFramer.frameSize * 2 + 17)).map(Float.init)

        let frames = framer.append(samples)

        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0.count == VoiceActivitySampleFramer.frameSize })
        #expect(frames[0].first == 0)
        #expect(frames[1].first == Float(VoiceActivitySampleFramer.frameSize))
        #expect(framer.bufferedSampleCount == 17)
    }

    @Test("framer joins partial callbacks and reset discards buffered audio")
    func partialFramesAndReset() {
        var framer = VoiceActivitySampleFramer()
        #expect(framer.append(Array(repeating: 1, count: 2_000)).isEmpty)

        framer.reset()
        let frames = framer.append(Array(repeating: 2, count: VoiceActivitySampleFramer.frameSize))

        #expect(frames == [Array(repeating: 2, count: VoiceActivitySampleFramer.frameSize)])
        #expect(framer.bufferedSampleCount == 0)
    }

    @Test(
        "converter produces 16 kHz mono float samples",
        arguments: [16_000.0, 44_100.0, 48_000.0], [AVAudioChannelCount(1), 2]
    )
    func conversion(sampleRate: Double, channels: AVAudioChannelCount) throws {
        let converter = VoiceActivityAudioConverter()
        let frameCount = AVAudioFrameCount(sampleRate / 4)
        let buffer = try #require(
            makeBuffer(
                sampleRate: sampleRate,
                channels: channels,
                frameCount: frameCount
            ))

        let samples = try converter.convert(buffer)
        let allSamplesAreFinite = samples.allSatisfy { $0.isFinite }

        #expect(abs(samples.count - 4_000) <= 8)
        #expect(allSamplesAreFinite)
    }

    @Test("model locator resolves only the audited compiled model directory")
    func modelLocator() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model =
            root
            .appendingPathComponent("Models/voice-activity-detection", isDirectory: true)
            .appendingPathComponent(
                BundledVoiceActivityModelLocator.modelDirectoryName,
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(BundledVoiceActivityModelLocator(resourceURL: root).modelURL == model)
        #expect(BundledVoiceActivityModelLocator(resourceURL: nil).modelURL == nil)
    }

    @Test("capture queue retains only its two newest buffers and reports overflow")
    func boundedCaptureQueue() async {
        let queue = VoiceActivityBufferQueue<Int>()

        #expect(queue.enqueue(1))
        #expect(queue.enqueue(2))
        #expect(!queue.enqueue(3))
        queue.finish()

        var values: [Int] = []
        for await value in queue.stream {
            values.append(value)
        }

        #expect(VoiceActivityBufferQueue<Int>.capacity == 2)
        #expect(values == [2, 3])
    }

    private func makeBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.floatChannelData
        else {
            return nil
        }

        buffer.frameLength = frameCount
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frameCount) {
                channelData[channel][frame] = sin(Float(frame) * 0.01) * 0.25
            }
        }
        return buffer
    }
}
