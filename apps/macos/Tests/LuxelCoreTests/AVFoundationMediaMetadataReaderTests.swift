import AVFAudio
import CoreMedia
import Foundation
import LuxelTestSupport
import Testing

@testable import LuxelCore

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
        #expect(
            AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_HEVCWithAlpha))
        #expect(
            AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_AppleProRes4444))
        #expect(
            AVFoundationMediaMetadataReader.mediaSubTypeSupportsAlpha(kCMVideoCodecType_AppleProRes4444XQ)
        )
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
        let fileURL = try makeSilentAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let result = await reader.inspectRecording(at: fileURL)

        #expect(result == .playable)
    }

    @Test("reader loads audio-only source metadata")
    func readerLoadsAudioOnlySourceMetadata() async throws {
        let reader = AVFoundationMediaMetadataReader()
        let fileURL = try makeSilentAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let source = try await reader.readSourceMedia(at: fileURL)

        #expect(!source.hasVideo)
        #expect(source.isAudioOnly)
        #expect(source.hasAudio)
        #expect(source.audioTracks == [.microphone])
        #expect(source.duration > 0.20)
        #expect(source.duration < 0.30)
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
        try sharedFixtureURL(fileName)
    }

    private func writeSilentAudioFixture(to fileURL: URL) throws {
        try writeSilentTestAAC(to: fileURL, duration: 0.25)
    }

    private func makeSilentAudioFixture() throws -> URL {
        let fileURL = temporaryTestFileURL(pathExtension: "m4a")
        try writeSilentAudioFixture(to: fileURL)
        return fileURL
    }
}
