import Foundation
import LuxelCodecWebM
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("WebM codec stack", .serialized)
struct WebMCodecStackTests {
    @Test("codec pipeline writes a WebM file with real VP9 and Opus packets")
    func codecPipelineWritesWebMFile() async throws {
        let outputURL = temporaryWebMURL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let pipeline = makeWebMTestPipeline(pixelSize: pixelSize)

        let exported = try await pipeline.export(
            makeRequest(pixelSize: pixelSize, shouldMute: false),
            to: outputURL
        )
        let data = try Data(contentsOf: outputURL)

        #expect(exported.format == .webm)
        #expect(exported.pixelSize == pixelSize)
        #expect(!exported.shouldMute)
        #expect(data.count > 200)
        #expect(data.starts(with: Data([0x1A, 0x45, 0xDF, 0xA3])))
        #expect(data.contains(Data("webm".utf8)))
        #expect(data.contains(Data("V_VP9".utf8)))
        #expect(data.contains(Data("A_OPUS".utf8)))
        #expect(data.contains(Data("OpusHead".utf8)))

        let document = try WebMTestDocument(data: data)
        try assertSeekEntriesResolve(in: document)
        try assertTracks(in: document, includeAudio: true)
        try assertCuesResolveToClusters(in: document)

        let info = try document.topLevelElement(WebMTestID.info)
        #expect(
            try document.unsigned(document.firstChild(WebMTestID.timestampScale, in: info)) == 1_000_000)
        #expect(try document.double(document.firstChild(WebMTestID.duration, in: info)) > 0)
        #expect(Int(document.segment.size) == document.segment.payloadRange.count)
    }

    @Test("media exporter writes a WebM fixture clip with audio")
    func mediaExporterWritesWebMFixtureClipWithAudio() async throws {
        let outputURL = temporaryWebMURL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .webm,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(60),
            timeRange: TimeRange(start: 0, end: 2.2),
            shouldMute: false,
            shouldCrop: false
        )

        let exported = try await WebMMediaExporter().export(request, to: outputURL)
        let data = try Data(contentsOf: outputURL)

        #expect(exported.fileURL == outputURL)
        #expect(exported.format == .webm)
        #expect(!exported.shouldMute)
        #expect(data.contains(Data("V_VP9".utf8)))
        #expect(data.contains(Data("A_OPUS".utf8)))

        let document = try WebMTestDocument(data: data)
        try assertTracks(in: document, includeAudio: true)
        try assertCuesResolveToClusters(in: document)
    }

    @Test("media exporter consumes prepared audio when the source has no audio")
    func mediaExporterConsumesPreparedAudio() async throws {
        let outputURL = temporaryWebMURL()
        let prepared = try makePreparedAudioTestInput(format: .webm)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: prepared.preparedURL)
        }

        let exported = try await WebMMediaExporter().export(
            prepared.input,
            to: outputURL
        )
        let data = try Data(contentsOf: outputURL)

        #expect(!exported.shouldMute)
        #expect(data.contains(Data("A_OPUS".utf8)))
        try assertTracks(in: WebMTestDocument(data: data), includeAudio: true)
    }

    @Test("codec adapter registration exposes WebM")
    func codecAdapterRegistrationExposesWebM() throws {
        let registry = try CodecAdapterRegistry(registrations: [
            try WebMCodecAdapter.registration()
        ])

        #expect(
            registry.availability.availableExportFormats
                == [.webm, .hevc, .mp4, .proRes422, .proRes4444, .gif, .apng])
    }

    @Test("muxer writes Cues and SeekHead entries that resolve to real segment positions")
    func muxerWritesSeekableDurationClusters() async throws {
        let outputURL = temporaryWebMURL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await writeTestWebMVideo(
            to: outputURL,
            frameCount: 150,
            byteCount: 256,
            keyframeInterval: 60
        )

        let document = try WebMTestDocument(data: try Data(contentsOf: outputURL))
        let clusters = document.topLevelElements(WebMTestID.cluster)
        let cues = try document.cuePoints()

        #expect(clusters.count >= 3)
        #expect(cues.count >= 3)
        try assertSeekEntriesResolve(in: document)
        try assertTracks(in: document, includeAudio: false)
        try assertCuesResolveToClusters(in: document)
    }

    @Test("muxer rolls clusters at the size cap without retaining the full export")
    func muxerRollsClustersAtSizeCap() async throws {
        let outputURL = temporaryWebMURL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await writeTestWebMVideo(
            to: outputURL,
            frameCount: 10,
            byteCount: 350_000,
            keyframeInterval: 1
        )

        let document = try WebMTestDocument(data: try Data(contentsOf: outputURL))
        let clusters = document.topLevelElements(WebMTestID.cluster)

        #expect(clusters.count >= 3)
        for cluster in clusters {
            let simpleBlocks = try document.children(of: cluster).filter {
                $0.id == WebMTestID.simpleBlock
            }
            #expect(!simpleBlocks.isEmpty)
            #expect(cluster.payloadRange.count <= 1_400_000)
        }
        try assertSeekEntriesResolve(in: document)
        try assertCuesResolveToClusters(in: document)
    }

    @Test("ffprobe accepts the generated WebM when installed")
    func ffprobeAcceptsGeneratedWebM() async throws {
        guard let ffprobe = ffprobePath() else {
            return
        }

        let outputURL = temporaryWebMURL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let pipeline = makeWebMTestPipeline(pixelSize: pixelSize)

        _ = try await pipeline.export(
            makeRequest(pixelSize: pixelSize, shouldMute: false),
            to: outputURL
        )

        let output = try runFFProbe(ffprobe: ffprobe, fileURL: outputURL)
        #expect(output.contains("\"format_name\": \"matroska,webm\""))
        #expect(output.contains("\"codec_name\": \"vp9\""))
        #expect(output.contains("\"codec_name\": \"opus\""))
    }

    @Test("ffmpeg decodes generated WebM above the PSNR floor when installed")
    func ffmpegDecodesGeneratedWebMAbovePSNRFloor() async throws {
        guard let ffmpeg = executablePath(named: "ffmpeg") else {
            return
        }

        let outputURL = temporaryWebMURL()
        let referenceURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("yuv")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: referenceURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let frameCount = 12
        try writeReferenceYUV(pixelSize: pixelSize, frameCount: frameCount, to: referenceURL)

        let pipeline = CodecExportPipeline(
            mediaSource: PatternWebMMediaSource(pixelSize: pixelSize, frameCount: frameCount),
            videoEncoder: VPXVideoEncoder(),
            muxer: WebMMuxer()
        )

        _ = try await pipeline.export(
            makeRequest(pixelSize: pixelSize, shouldMute: true, quality: .high),
            to: outputURL
        )

        let psnrOutput = try runFFmpegPSNR(
            ffmpeg: ffmpeg,
            referenceURL: referenceURL,
            encodedURL: outputURL,
            pixelSize: pixelSize
        )
        let psnr = try #require(parseAveragePSNR(psnrOutput))
        #expect(psnr >= 38)
    }

}
