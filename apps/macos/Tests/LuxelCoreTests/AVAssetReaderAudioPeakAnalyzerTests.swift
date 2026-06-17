import AVFAudio
import Foundation
import LuxelCore
import Testing

@Suite("AVAssetReader audio peak analyzer")
struct AVAssetReaderAudioPeakAnalyzerTests {
    @Test("analyzer measures peak inside requested time range")
    func analyzerMeasuresPeakInsideRequestedTimeRange() async throws {
        let fileURL = try writePeakFixture()
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let analyzer = AVAssetReaderAudioPeakAnalyzer()

        let firstHalfPeaks = try await analyzer.measurePeaks(AudioPeakAnalysisRequest(
            inputFileURL: fileURL,
            timeRange: TimeRange(start: 0, end: 0.5),
            audioTracks: [.system]
        ))
        let secondHalfPeaks = try await analyzer.measurePeaks(AudioPeakAnalysisRequest(
            inputFileURL: fileURL,
            timeRange: TimeRange(start: 0.5, end: 1),
            audioTracks: [.system, .microphone, .system]
        ))

        #expect(isApproximately(firstHalfPeaks[.system], 0.25))
        #expect(isApproximately(secondHalfPeaks[.system], 0.75))
        #expect(isApproximately(secondHalfPeaks[.microphone], 0.75))
        #expect(secondHalfPeaks.count == 2)
    }

    @Test("analyzer returns zeros when media has no audio tracks")
    func analyzerReturnsZerosWhenMediaHasNoAudioTracks() async throws {
        let analyzer = AVAssetReaderAudioPeakAnalyzer()

        let peaks = try await analyzer.measurePeaks(AudioPeakAnalysisRequest(
            inputFileURL: try fixtureURL("input.mp4"),
            timeRange: TimeRange(start: 0, end: 0.5),
            audioTracks: [.system]
        ))

        #expect(peaks == [.system: 0])
    }

    @Test("analyzer ignores empty track requests")
    func analyzerIgnoresEmptyTrackRequests() async throws {
        let analyzer = AVAssetReaderAudioPeakAnalyzer()

        let peaks = try await analyzer.measurePeaks(AudioPeakAnalysisRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/missing.wav"),
            timeRange: TimeRange(start: 0, end: 1),
            audioTracks: []
        ))

        #expect(peaks.isEmpty)
    }

    private func writePeakFixture() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "luxel-peak-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let sampleRate = 48_000.0
        let frameCount = AVAudioFrameCount(sampleRate)
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?[0])

        for frame in 0..<Int(frameCount) {
            samples[frame] = frame < Int(frameCount) / 2 ? 0.25 : -0.75
        }

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        try file.write(from: buffer)
        return fileURL
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }

    private func isApproximately(
        _ lhs: Double?,
        _ rhs: Double,
        tolerance: Double = 0.01
    ) -> Bool {
        guard let lhs else {
            return false
        }

        return abs(lhs - rhs) <= tolerance
    }
}
