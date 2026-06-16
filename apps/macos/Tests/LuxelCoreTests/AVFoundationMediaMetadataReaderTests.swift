import Foundation
import AVFAudio
import CoreMedia
@testable import LuxelCore
import Testing

@Suite("AVFoundation media metadata reader")
struct AVFoundationMediaMetadataReaderTests {
    @Test("reader loads source metadata from reference fixture")
    func readerLoadsSourceMetadataFromReferenceFixture() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let source = try await reader.readSourceMedia(at: fixtureURL("input.mp4"))
        let expectedPixelSize = try PixelSize(width: 2560, height: 1440)
        let expectedFrameRate = try FrameRate(59)

        #expect(source.fileURL.lastPathComponent == "input.mp4")
        #expect(source.duration > 106)
        #expect(source.duration < 107)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(!source.hasAudio)
        #expect(source.audioTracks.isEmpty)
        #expect(!source.hasAlpha)
    }

    @Test("reader detects audio tracks")
    func readerDetectsAudioTracks() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let source = try await reader.readSourceMedia(at: fixtureURL("input@2x.mp4"))

        #expect(source.hasAudio)
        #expect(source.audioTracks == [.system])
        #expect(!source.hasAlpha)
    }

    @Test("reader classifies alpha-capable video media subtypes")
    func readerClassifiesAlphaCapableVideoMediaSubtypes() {
        #expect(AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_HEVCWithAlpha))
        #expect(AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_AppleProRes4444))
        #expect(AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_AppleProRes4444XQ))
        #expect(!AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_H264))
        #expect(!AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_HEVC))
    }

    @Test("probe treats readable incomplete recording as playable")
    func probeTreatsReadableIncompleteRecordingAsPlayable() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let result = await reader.inspectRecording(at: try fixtureURL("incomplete.mp4"))

        #expect(result == .playable)
    }

    @Test("probe treats audio-only recordings as playable")
    func probeTreatsAudioOnlyRecordingsAsPlayable() async throws {
        let reader = AVFoundationMediaMetadataReader()
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("m4a")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try writeSilentAudioFixture(to: fileURL)

        let result = await reader.inspectRecording(at: fileURL)

        #expect(result == .playable)
    }

    @Test("probe reports corrupt recordings")
    func probeReportsCorruptRecordings() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let result = await reader.inspectRecording(at: try fixtureURL("corrupt.mp4"))

        guard case .corrupt(let reason) = result else {
            Issue.record("Expected corrupt result")
            return
        }

        #expect(!reason.isEmpty)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
    }

    private func writeSilentAudioFixture(to fileURL: URL) throws {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate / 4)
        let pcmFormat = try #require(AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
        )
        try file.write(from: buffer)
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
}
