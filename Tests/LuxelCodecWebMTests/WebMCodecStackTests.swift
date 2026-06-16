import Foundation
import LuxelCodecWebM
import LuxelCore
import Testing

@Suite("WebM codec stack")
struct WebMCodecStackTests {
    @Test("codec pipeline writes a WebM file with real VP9 and Opus packets")
    func codecPipelineWritesWebMFile() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("webm")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let pipeline = CodecExportPipeline(
            mediaSource: StubWebMMediaSource(pixelSize: pixelSize),
            videoEncoder: VPXVideoEncoder(),
            audioEncoder: OpusAudioEncoder(),
            muxer: WebMMuxer()
        )

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
        #expect(try document.unsigned(document.firstChild(WebMTestID.timestampScale, in: info)) == 1_000_000)
        #expect(try document.double(document.firstChild(WebMTestID.duration, in: info)) > 0)
        #expect(Int(document.segment.size) == document.segment.payloadRange.count)
    }

    @Test("codec adapter registration exposes WebM")
    func codecAdapterRegistrationExposesWebM() throws {
        let registry = try CodecAdapterRegistry(registrations: [
            try WebMCodecAdapter.registration()
        ])

        #expect(registry.availability.availableExportFormats == [.mp4, .hevc, .gif, .apng, .webm])
    }

    @Test("muxer writes Cues and SeekHead entries that resolve to real segment positions")
    func muxerWritesSeekableDurationClusters() async throws {
        let outputURL = temporaryWebMURL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let muxer = WebMMuxer()
        try await muxer.begin(try CodecMuxerConfiguration(
            outputFileURL: outputURL,
            format: .webm,
            tracks: [.video],
            pixelSize: PixelSize(width: 64, height: 64)
        ))

        for index in 0..<150 {
            try await muxer.write(fakeVideoPacket(index: index, byteCount: 256, keyframeInterval: 60), to: .video)
        }
        try await muxer.finalize()

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

        let muxer = WebMMuxer()
        try await muxer.begin(try CodecMuxerConfiguration(
            outputFileURL: outputURL,
            format: .webm,
            tracks: [.video],
            pixelSize: PixelSize(width: 64, height: 64)
        ))

        for index in 0..<10 {
            try await muxer.write(fakeVideoPacket(index: index, byteCount: 350_000, keyframeInterval: 1), to: .video)
        }
        try await muxer.finalize()

        let document = try WebMTestDocument(data: try Data(contentsOf: outputURL))
        let clusters = document.topLevelElements(WebMTestID.cluster)

        #expect(clusters.count >= 3)
        for cluster in clusters {
            let simpleBlocks = try document.children(of: cluster).filter { $0.id == WebMTestID.simpleBlock }
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
        let pipeline = CodecExportPipeline(
            mediaSource: StubWebMMediaSource(pixelSize: pixelSize),
            videoEncoder: VPXVideoEncoder(),
            audioEncoder: OpusAudioEncoder(),
            muxer: WebMMuxer()
        )

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

    private func makeRequest(
        pixelSize: PixelSize,
        shouldMute: Bool,
        quality: ExportQuality = .compact
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: .webm,
            pixelSize: pixelSize,
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 0.1),
            shouldMute: shouldMute,
            shouldCrop: false,
            quality: quality
        )
    }

    private func temporaryWebMURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("webm")
    }

    private func fakeVideoPacket(index: Int, byteCount: Int, keyframeInterval: Int) throws -> EncodedPacket {
        try EncodedPacket(
            data: Data(repeating: UInt8(index % 255), count: byteCount),
            presentationTime: Double(index) / 30,
            duration: 1 / 30,
            isKeyFrame: index.isMultiple(of: keyframeInterval)
        )
    }

    private func assertSeekEntriesResolve(in document: WebMTestDocument) throws {
        let entries = try document.seekEntries()
        let targetIDs = Set(entries.map(\.targetID))

        #expect(targetIDs.contains(WebMTestID.info))
        #expect(targetIDs.contains(WebMTestID.tracks))
        #expect(targetIDs.contains(WebMTestID.cluster))
        #expect(targetIDs.contains(WebMTestID.cues))

        for entry in entries {
            #expect(document.element(atSegmentPosition: entry.position)?.id == entry.targetID)
        }
    }

    private func assertTracks(in document: WebMTestDocument, includeAudio: Bool) throws {
        let tracks = try document.topLevelElement(WebMTestID.tracks)
        let trackEntries = try document.children(of: tracks).filter { $0.id == WebMTestID.trackEntry }
        let codecIDs = try trackEntries.map { trackEntry in
            try document.string(document.firstChild(WebMTestID.codecID, in: trackEntry))
        }

        #expect(codecIDs.contains("V_VP9"))
        #expect(codecIDs.contains("A_OPUS") == includeAudio)

        let videoTrack = try #require(trackEntries.first { trackEntry in
            (try? document.string(document.firstChild(WebMTestID.codecID, in: trackEntry))) == "V_VP9"
        })
        let video = try document.firstChild(WebMTestID.video, in: videoTrack)
        _ = try document.firstChild(WebMTestID.colour, in: video)

        if includeAudio {
            let audioTrack = try #require(trackEntries.first { trackEntry in
                (try? document.string(document.firstChild(WebMTestID.codecID, in: trackEntry))) == "A_OPUS"
            })
            let codecPrivate = try document.binary(document.firstChild(WebMTestID.codecPrivate, in: audioTrack))
            #expect(codecPrivate.starts(with: Data("OpusHead".utf8)))
        }
    }

    private func assertCuesResolveToClusters(in document: WebMTestDocument) throws {
        let cues = try document.cuePoints()
        #expect(!cues.isEmpty)

        for cue in cues {
            #expect(cue.track == 1)
            #expect(document.element(atSegmentPosition: cue.clusterPosition)?.id == WebMTestID.cluster)
        }
    }

    private func ffprobePath() -> String? {
        executablePath(named: "ffprobe")
    }

    private func executablePath(named name: String) -> String? {
        let fileSystem = FileManager.default
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]

        return searchPaths
            .map { URL(fileURLWithPath: $0).appending(path: name).path }
            .first { fileSystem.isExecutableFile(atPath: $0) }
    }

    private func runFFProbe(ffprobe: String, fileURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error",
            "-show_format",
            "-show_streams",
            "-of", "json",
            fileURL.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        _ = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        return output
    }

    private func writeReferenceYUV(pixelSize: PixelSize, frameCount: Int, to fileURL: URL) throws {
        var data = Data()
        for index in 0..<frameCount {
            let frame = try makePatternFrame(index: index, pixelSize: pixelSize)
            data.append(frame.yPlane)
            data.append(frame.uPlane)
            data.append(frame.vPlane)
        }
        try data.write(to: fileURL)
    }

    private func runFFmpegPSNR(
        ffmpeg: String,
        referenceURL: URL,
        encodedURL: URL,
        pixelSize: PixelSize
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-hide_banner",
            "-nostats",
            "-f", "rawvideo",
            "-pixel_format", "yuv420p",
            "-video_size", "\(pixelSize.width)x\(pixelSize.height)",
            "-framerate", "30",
            "-i", referenceURL.path,
            "-i", encodedURL.path,
            "-filter_complex", "[0:v][1:v]psnr",
            "-f", "null",
            "-"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        return output + "\n" + error
    }

    private func parseAveragePSNR(_ output: String) -> Double? {
        guard let range = output.range(of: "average:") else {
            return nil
        }

        let suffix = output[range.upperBound...]
        let value = suffix.prefix { !$0.isWhitespace }
        if value == "inf" {
            return .infinity
        }
        return Double(value)
    }
}

private actor StubWebMMediaSource: CodecMediaSource {
    private let pixelSize: PixelSize
    private var didEmitVideoFrame = false
    private var didEmitAudioChunk = false

    init(pixelSize: PixelSize) {
        self.pixelSize = pixelSize
    }

    func prepare(_ request: ExportRequest) async throws -> CodecMediaSourceDescription {
        try CodecMediaSourceDescription(
            videoFrameCount: 1,
            audioChunkCount: request.outputShouldMute ? 0 : 1,
            audioSampleRate: request.outputShouldMute ? nil : 48_000,
            audioChannelCount: request.outputShouldMute ? nil : 2
        )
    }

    func nextVideoFrame() async throws -> CodecVideoFrame? {
        guard !didEmitVideoFrame else {
            return nil
        }
        didEmitVideoFrame = true

        let yPlane = Data(repeating: 128, count: pixelSize.width * pixelSize.height)
        let chromaPlane = Data(repeating: 128, count: pixelSize.width * pixelSize.height / 4)
        return try CodecVideoFrame(
            frame: I420Frame(
                pixelSize: pixelSize,
                yPlane: yPlane,
                uPlane: chromaPlane,
                vPlane: chromaPlane
            ),
            presentationTime: 0,
            duration: 1 / 30
        )
    }

    func nextAudioChunk() async throws -> CodecAudioChunk? {
        guard !didEmitAudioChunk else {
            return nil
        }
        didEmitAudioChunk = true

        return try CodecAudioChunk(
            pcmData: Data(repeating: 0, count: 960 * 2 * MemoryLayout<Int16>.size),
            presentationTime: 0,
            duration: 0.02
        )
    }
}

private actor PatternWebMMediaSource: CodecMediaSource {
    private let pixelSize: PixelSize
    private let frameCount: Int
    private var nextFrameIndex = 0

    init(pixelSize: PixelSize, frameCount: Int) {
        self.pixelSize = pixelSize
        self.frameCount = frameCount
    }

    func prepare(_ request: ExportRequest) async throws -> CodecMediaSourceDescription {
        try CodecMediaSourceDescription(videoFrameCount: frameCount)
    }

    func nextVideoFrame() async throws -> CodecVideoFrame? {
        guard nextFrameIndex < frameCount else {
            return nil
        }

        let index = nextFrameIndex
        nextFrameIndex += 1
        return try CodecVideoFrame(
            frame: makePatternFrame(index: index, pixelSize: pixelSize),
            presentationTime: Double(index) / 30,
            duration: 1 / 30
        )
    }

    func nextAudioChunk() async throws -> CodecAudioChunk? {
        nil
    }
}

private func makePatternFrame(index: Int, pixelSize: PixelSize) throws -> I420Frame {
    var yPlane = Data()
    yPlane.reserveCapacity(pixelSize.width * pixelSize.height)
    yPlane.append(Data(repeating: UInt8(128 + (index % 2)), count: pixelSize.width * pixelSize.height))

    let chromaWidth = pixelSize.width / 2
    let chromaHeight = pixelSize.height / 2
    let uPlane = Data(repeating: 128, count: chromaWidth * chromaHeight)
    let vPlane = Data(repeating: 128, count: chromaWidth * chromaHeight)

    return try I420Frame(pixelSize: pixelSize, yPlane: yPlane, uPlane: uPlane, vPlane: vPlane)
}
