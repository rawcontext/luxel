import AVFAudio
import AVFoundation
import AppKit
import CoreMedia
import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation media exporter", .serialized)
struct AVFoundationMediaExporterTests {
}

extension AVFoundationMediaExporterTests {
    @Test("MP4 export renders keystroke chips only during their mapped interval")
    func mp4ExportRendersKeystrokeChipsOnlyDuringMappedInterval() async throws {
        let inputURL = temporaryOutputURL(fileExtension: "mp4")
        let overlayURL = temporaryOutputURL(fileExtension: "mp4")
        let sidecarURL = KeystrokeSidecarDocument.sidecarURL(nextTo: inputURL)
        defer {
            for url in [inputURL, overlayURL, sidecarURL] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try await writeSplitColorMovie(to: inputURL)
        let timeline = try KeystrokeTimeline(events: [
            KeystrokeEvent(
                time: 0.1,
                kind: .keyDown,
                keyCode: 40,
                characters: "k",
                modifiers: [.command]
            )
        ])
        try JSONEncoder().encode(KeystrokeSidecarDocument(timeline: timeline))
            .write(to: sidecarURL, options: .atomic)
        let overlayRequest = try ExportRequest(
            inputFileURL: inputURL,
            format: .mp4,
            pixelSize: PixelSize(width: 64, height: 64),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 0, end: 0.8),
            shouldMute: true,
            shouldCrop: false,
            keystrokeOptions: KeystrokeRenderOptions(displayDuration: 0.5)
        )

        _ = try await AVFoundationMediaExporter().export(overlayRequest, to: overlayURL)

        let overlayActive = try await framePixelData(at: overlayURL, time: 0.3)
        let overlayBefore = try await framePixelData(at: overlayURL, time: 0)
        let overlayAfter = try await framePixelData(at: overlayURL, time: 0.7)
        let activeDifference = meanAbsolutePixelDifference(overlayActive, overlayBefore)
        let outsideDifference = meanAbsolutePixelDifference(overlayBefore, overlayAfter)
        #expect(activeDifference > 5)
        #expect(outsideDifference < 2)
        #expect(activeDifference > outsideDifference * 10)
    }

    @Test("mp4 export trims resizes changes frame rate and keeps audio")
    func mp4ExportTrimsResizesChangesFrameRateAndKeepsAudio() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 321, height: 181),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.75),
            shouldMute: false,
            shouldCrop: true
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)
        let expectedFrameRate = try FrameRate(30)

        #expect(exported.fileURL == outputURL)
        #expect(exported.format == .mp4)
        #expect(exported.pixelSize == expectedPixelSize)
        #expect(!exported.shouldMute)
        #expect(source.duration > 0.70)
        #expect(source.duration < 0.80)
        #expect(source.pixelSize == exported.pixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(source.hasAudio)
        let codecType = try await videoCodecType(at: outputURL)
        #expect(codecType == kCMVideoCodecType_H264)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("hevc export writes HEVC video")
    func hevcExportWritesHEVCVideo() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .hevc,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.5),
            shouldMute: true,
            shouldCrop: false
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)
        let codecType = try await videoCodecType(at: outputURL)

        #expect(exported.format == .hevc)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(codecType == kCMVideoCodecType_HEVC)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("ProRes exports write requested codecs")
    func proResExportsWriteRequestedCodecs() async throws {
        let expectations: [(format: ExportFormat, codecType: CMVideoCodecType)] = [
            (.proRes422, kCMVideoCodecType_AppleProRes422),
            (.proRes4444, kCMVideoCodecType_AppleProRes4444)
        ]

        for expectation in expectations {
            let outputURL = temporaryOutputURL(fileExtension: expectation.format.fileExtension)
            let request = try ExportRequest(
                inputFileURL: fixtureURL("input.mp4"),
                format: expectation.format,
                pixelSize: PixelSize(width: 320, height: 180),
                frameRate: FrameRate(30),
                timeRange: TimeRange(start: 1, end: 1.2),
                shouldMute: true,
                shouldCrop: false
            )

            let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
            let codecType = try await videoCodecType(at: outputURL)

            #expect(exported.format == expectation.format)
            #expect(exported.fileURL.pathExtension == "mov")
            #expect(codecType == expectation.codecType)

            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    @Test("muted mp4 export omits audio tracks")
    func mutedMP4ExportOmitsAudioTracks() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(24),
            timeRange: TimeRange(start: 2, end: 2.5),
            shouldMute: true,
            shouldCrop: false
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)
        let expectedFrameRate = try FrameRate(24)

        #expect(exported.shouldMute)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(!source.hasAudio)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("mp4 export applies playback speed to video and audio")
    func mp4ExportAppliesPlaybackSpeedToVideoAndAudio() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.8),
            shouldMute: false,
            shouldCrop: false,
            speed: PlaybackSpeed(2)
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)

        #expect(exported.fileURL == outputURL)
        #expect(source.duration > 0.35)
        #expect(source.duration < 0.45)
        #expect(source.hasAudio)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("mp4 export applies audio mix volume")
    func mp4ExportAppliesAudioMixVolume() async throws {
        let baselineURL = temporaryOutputURL(fileExtension: "mp4")
        let quietURL = temporaryOutputURL(fileExtension: "mp4")
        defer {
            try? FileManager.default.removeItem(at: baselineURL)
            try? FileManager.default.removeItem(at: quietURL)
        }
        let inputURL = try fixtureURL("input@2x.mp4")
        let timeRange = try TimeRange(start: 1, end: 1.8)
        let baselineRequest = try ExportRequest(
            inputFileURL: inputURL,
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: timeRange,
            shouldMute: false,
            shouldCrop: false
        )
        let quietRequest = try ExportRequest(
            inputFileURL: inputURL,
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: timeRange,
            shouldMute: false,
            audioMix: AudioMixPlan(tracks: [
                AudioTrackMix(kind: .system, volume: 0.2)
            ]),
            shouldCrop: false
        )

        _ = try await AVFoundationMediaExporter().export(baselineRequest, to: baselineURL)
        _ = try await AVFoundationMediaExporter().export(quietRequest, to: quietURL)

        let baselinePeak = try await audioPeak(
            at: baselineURL, duration: baselineRequest.outputDuration)
        let quietPeak = try await audioPeak(at: quietURL, duration: quietRequest.outputDuration)

        #expect(baselinePeak > 0.01)
        #expect(quietPeak < baselinePeak * 0.4)
    }

    @Test("native video and audio-only exports replace source audio with prepared PCM")
    func nativeExportsUsePreparedAudio() async throws {
        let preparedURL = temporaryOutputURL(fileExtension: "caf")
        let videoOutputURL = temporaryOutputURL(fileExtension: "mp4")
        let audioOutputURL = temporaryOutputURL(fileExtension: "wav")
        defer {
            try? FileManager.default.removeItem(at: preparedURL)
            try? FileManager.default.removeItem(at: videoOutputURL)
            try? FileManager.default.removeItem(at: audioOutputURL)
        }
        try writeSilentPCMFixture(to: preparedURL, duration: 0.4)
        let prepared = PreparedAudioAsset(
            fileURL: preparedURL,
            duration: 0.4,
            sampleRate: 48_000,
            channelCount: 2
        )
        let inputURL = try fixtureURL("input@2x.mp4")

        for (format, outputURL) in [
            (ExportFormat.mp4, videoOutputURL),
            (.wav, audioOutputURL)
        ] {
            let request = try ExportRequest(
                inputFileURL: inputURL,
                format: format,
                pixelSize: PixelSize(width: 320, height: 180),
                frameRate: FrameRate(30),
                timeRange: TimeRange(start: 1, end: 1.4),
                shouldMute: false,
                studioVoiceEnabled: true,
                shouldCrop: false
            )

            _ = try await AVFoundationMediaExporter().export(
                MediaExportInput(request: request, preparedAudio: prepared),
                to: outputURL
            )
            let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
            let peak = try await audioPeak(at: outputURL, duration: request.outputDuration)

            #expect(source.hasAudio)
            #expect(source.duration > 0.35)
            #expect(source.duration < 0.45)
            #expect(peak < 0.000_1)
        }
    }

    @Test("native audio exports trim audio-only source")
    func nativeAudioExportsTrimAudioOnlySource() async throws {
        let inputURL = temporaryOutputURL(fileExtension: "m4a")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try writeSilentAudioFixture(to: inputURL, duration: 1)
        let expectations: [(format: ExportFormat, codecType: FourCharCode)] = [
            (.m4a, kAudioFormatMPEG4AAC),
            (.alac, kAudioFormatAppleLossless),
            (.wav, kAudioFormatLinearPCM),
            (.caf, kAudioFormatLinearPCM),
            (.flac, kAudioFormatFLAC)
        ]

        for expectation in expectations {
            let outputURL = temporaryOutputURL(fileExtension: expectation.format.fileExtension)
            defer { try? FileManager.default.removeItem(at: outputURL) }
            let request = try ExportRequest(
                inputFileURL: inputURL,
                format: expectation.format,
                pixelSize: PixelSize(width: 1, height: 1),
                frameRate: FrameRate(1),
                timeRange: TimeRange(start: 0, end: 0.4),
                shouldMute: false,
                shouldCrop: false
            )

            let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
            let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
            let codecType = try await audioCodecType(at: outputURL)

            #expect(exported.fileURL == outputURL)
            #expect(exported.format == expectation.format)
            #expect(!exported.shouldMute)
            #expect(source.isAudioOnly)
            #expect(source.duration > 0.35)
            #expect(source.duration < 0.45)
            #expect(codecType == expectation.codecType)
        }
    }

    @Test("mp4 export applies zoom blocks to video composition")
    func mp4ExportAppliesZoomBlocksToVideoComposition() async throws {
        let inputURL = temporaryOutputURL(fileExtension: "mp4")
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await writeSplitColorMovie(to: inputURL)
        let sourceRightPixel = try await rgbPixel(at: inputURL, time: 1, x: 48, y: 32)
        let request = try ExportRequest(
            inputFileURL: inputURL,
            format: .mp4,
            pixelSize: PixelSize(width: 64, height: 64),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 0, end: 2),
            shouldMute: true,
            shouldCrop: true,
            zoomBlocks: [
                ZoomBlock(
                    timeRange: TimeRange(start: 0, end: 2),
                    targetRect: NormalizedRect(x: 0, y: 0.25, width: 0.5, height: 0.5),
                    zoom: 2,
                    transitionOverride: 0.1
                )
            ]
        )

        _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let zoomedRightPixel = try await rgbPixel(at: outputURL, time: 1, x: 48, y: 32)

        #expect(sourceRightPixel.blue > sourceRightPixel.red + 80)
        #expect(zoomedRightPixel.red > zoomedRightPixel.blue + 80)
    }

    @Test("h264 export uses compatibility profile metadata")
    func h264ExportUsesCompatibilityProfileMetadata() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 321, height: 181),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.75),
            shouldMute: false,
            shouldCrop: false,
            quality: .high
        )

        _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let formatDescription = try await firstVideoFormatDescription(at: outputURL)
        let extensions = try #require(
            CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any])
        let boxTypes = try topLevelBoxTypes(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)

        #expect(source.pixelSize == expectedPixelSize)
        #expect(CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_H264)
        #expect(try h264ProfileIDC(formatDescription: formatDescription) == 100)
        #expect(extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String] == nil)
        #expect(
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(
            extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
                == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
        #expect(try boxIndex("moov", in: boxTypes) < boxIndex("mdat", in: boxTypes))
    }

    @Test("unsupported formats are rejected without writing output")
    func unsupportedFormatsAreRejectedWithoutWritingOutput() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(12),
            timeRange: TimeRange(start: 1, end: 1.2),
            shouldMute: false,
            shouldCrop: false
        )

        await #expect(throws: AVFoundationExportPlanError.unsupportedFormat(.gif)) {
            _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }
}
