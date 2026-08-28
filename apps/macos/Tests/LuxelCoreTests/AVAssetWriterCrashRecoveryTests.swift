@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import LuxelTestSupport
import Testing

@testable import LuxelCore

@Suite("AVAssetWriter crash recovery")
struct AVAssetWriterCrashRecoveryTests {
    @Test("fragmented audio is playable before the writer finishes")
    func fragmentedAudioIsPlayableBeforeFinish() async throws {
        let sourceURL = temporaryTestFileURL(pathExtension: "caf")
        let outputURL = temporaryTestFileURL(pathExtension: "m4a")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try writeSilentTestPCM(to: sourceURL, duration: 12)

        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceTrack = try #require(
            await sourceAsset.loadTracks(withMediaType: .audio).first
        )
        let reader = try AVAssetReader(asset: sourceAsset)
        let readerOutput = AVAssetReaderTrackOutput(track: sourceTrack, outputSettings: nil)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        AVAssetWriterCrashRecovery.configure(writer)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000
            ]
        )
        writer.add(writerInput)

        #expect(reader.startReading())
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            #expect(writerInput.append(sampleBuffer))
        }

        try await Task.sleep(for: .milliseconds(100))
        let partialAsset = AVURLAsset(url: outputURL)
        let duration = try await partialAsset.load(.duration)

        #expect(duration.seconds >= 1)
        writer.cancelWriting()
    }

    @Test("audio recordings write an early fragment and periodic recovery fragments")
    func audioFragmentIntervals() throws {
        let outputURL = temporaryTestFileURL(pathExtension: "m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        AVAssetWriterCrashRecovery.configure(writer)

        #expect(writer.initialMovieFragmentInterval == CMTime(seconds: 1, preferredTimescale: 600))
        #expect(writer.movieFragmentInterval == CMTime(seconds: 10, preferredTimescale: 600))
    }

    @Test("video recordings write recovery fragments")
    func videoFragmentIntervals() throws {
        let outputURL = temporaryTestFileURL(pathExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        AVAssetWriterCrashRecovery.configure(writer)

        #expect(writer.initialMovieFragmentInterval == CMTime(seconds: 1, preferredTimescale: 600))
        #expect(writer.movieFragmentInterval == CMTime(seconds: 10, preferredTimescale: 600))
    }
}
