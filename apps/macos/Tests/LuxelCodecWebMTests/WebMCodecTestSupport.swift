import Foundation
import LuxelCodecWebM
import LuxelCore
import LuxelTestSupport
import Testing

func makeRequest(
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

func temporaryWebMURL() -> URL {
    temporaryTestFileURL(pathExtension: "webm")
}

func fixtureURL(_ fileName: String) throws -> URL {
    try testFixtureURL(fileName)
}

func packageRootURL() throws -> URL {
    try testPackageRootURL()
}

func fakeVideoPacket(index: Int, byteCount: Int, keyframeInterval: Int) throws
-> EncodedPacket {
    try EncodedPacket(
        data: Data(repeating: UInt8(index % 255), count: byteCount),
        presentationTime: Double(index) / 30,
        duration: 1 / 30,
        isKeyFrame: index.isMultiple(of: keyframeInterval)
    )
}

func assertSeekEntriesResolve(in document: WebMTestDocument) throws {
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

func assertTracks(in document: WebMTestDocument, includeAudio: Bool) throws {
    let tracks = try document.topLevelElement(WebMTestID.tracks)
    let trackEntries = try document.children(of: tracks).filter { $0.id == WebMTestID.trackEntry }
    let codecIDs = try trackEntries.map { trackEntry in
        try document.string(document.firstChild(WebMTestID.codecID, in: trackEntry))
    }

    #expect(codecIDs.contains("V_VP9"))
    #expect(codecIDs.contains("A_OPUS") == includeAudio)

    let videoTrack = try #require(
        trackEntries.first { trackEntry in
            (try? document.string(document.firstChild(WebMTestID.codecID, in: trackEntry))) == "V_VP9"
        })
    let video = try document.firstChild(WebMTestID.video, in: videoTrack)
    _ = try document.firstChild(WebMTestID.colour, in: video)

    if includeAudio {
        let audioTrack = try #require(
            trackEntries.first { trackEntry in
                (try? document.string(document.firstChild(WebMTestID.codecID, in: trackEntry))) == "A_OPUS"
            })
        let codecPrivate = try document.binary(
            document.firstChild(WebMTestID.codecPrivate, in: audioTrack))
        #expect(codecPrivate.starts(with: Data("OpusHead".utf8)))
    }
}

func assertCuesResolveToClusters(in document: WebMTestDocument) throws {
    let cues = try document.cuePoints()
    #expect(!cues.isEmpty)

    for cue in cues {
        #expect(cue.track == 1)
        #expect(document.element(atSegmentPosition: cue.clusterPosition)?.id == WebMTestID.cluster)
    }
}

func ffprobePath() -> String? {
    executablePath(named: "ffprobe")
}

func executablePath(named name: String) -> String? {
    testExecutablePath(named: name)
}

func runFFProbe(ffprobe: String, fileURL: URL) throws -> String {
    let result = try runTestFFProbe(executable: ffprobe, fileURL: fileURL)
    #expect(result.terminationStatus == 0)
    return result.output
}

func makeWebMTestPipeline(pixelSize: PixelSize) -> CodecExportPipeline {
    CodecExportPipeline(
        mediaSource: StubWebMMediaSource(pixelSize: pixelSize),
        videoEncoder: VPXVideoEncoder(),
        audioEncoder: OpusAudioEncoder(),
        muxer: WebMMuxer()
    )
}

func writeTestWebMVideo(
    to outputURL: URL,
    frameCount: Int,
    byteCount: Int,
    keyframeInterval: Int
) async throws {
    let muxer = WebMMuxer()
    try await muxer.begin(
        try CodecMuxerConfiguration(
            outputFileURL: outputURL,
            format: .webm,
            tracks: [.video],
            pixelSize: PixelSize(width: 64, height: 64)
        ))
    for index in 0..<frameCount {
        try await muxer.write(
            fakeVideoPacket(
                index: index,
                byteCount: byteCount,
                keyframeInterval: keyframeInterval
            ),
            to: .video
        )
    }
    try await muxer.finalize()
}

func writeReferenceYUV(pixelSize: PixelSize, frameCount: Int, to fileURL: URL) throws {
    var data = Data()
    for index in 0..<frameCount {
        let frame = try makePatternFrame(index: index, pixelSize: pixelSize)
        data.append(frame.yPlane)
        data.append(frame.uPlane)
        data.append(frame.vPlane)
    }
    try data.write(to: fileURL)
}

func runFFmpegPSNR(
    ffmpeg: String,
    referenceURL: URL,
    encodedURL: URL,
    pixelSize: PixelSize
) throws -> String {
    let result = try runTestProcess(executable: ffmpeg, arguments: [
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
    ])
    #expect(result.terminationStatus == 0)
    return result.output + "\n" + result.error
}

func parseAveragePSNR(_ output: String) -> Double? {
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

actor StubWebMMediaSource: CodecMediaSource {
    private let pixelSize: PixelSize
    private var didEmitVideoFrame = false
    private var didEmitAudioChunk = false

    init(pixelSize: PixelSize) {
        self.pixelSize = pixelSize
    }

    func prepare(_ input: MediaExportInput) async throws -> CodecMediaSourceDescription {
        let request = input.request
        return try CodecMediaSourceDescription(
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

actor PatternWebMMediaSource: CodecMediaSource {
    private let pixelSize: PixelSize
    private let frameCount: Int
    private var nextFrameIndex = 0

    init(pixelSize: PixelSize, frameCount: Int) {
        self.pixelSize = pixelSize
        self.frameCount = frameCount
    }

    func prepare(_ input: MediaExportInput) async throws -> CodecMediaSourceDescription {
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

func makePatternFrame(index: Int, pixelSize: PixelSize) throws -> I420Frame {
    var yPlane = Data()
    yPlane.reserveCapacity(pixelSize.width * pixelSize.height)
    yPlane.append(
        Data(repeating: UInt8(128 + (index % 2)), count: pixelSize.width * pixelSize.height))

    let chromaWidth = pixelSize.width / 2
    let chromaHeight = pixelSize.height / 2
    let uPlane = Data(repeating: 128, count: chromaWidth * chromaHeight)
    let vPlane = Data(repeating: 128, count: chromaWidth * chromaHeight)

    return try I420Frame(pixelSize: pixelSize, yPlane: yPlane, uPlane: uPlane, vPlane: vPlane)
}
