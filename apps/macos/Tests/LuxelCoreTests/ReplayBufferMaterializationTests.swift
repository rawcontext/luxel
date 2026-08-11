import AVFoundation
import CoreVideo
import Foundation
@testable import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Replay buffer materialization", .serialized)
struct ReplayBufferMaterializationTests {
    @Test("standalone clips rebase host-clock timestamps", arguments: [0.0, 0.5])
    func standaloneClipsRebaseHostClockTimestamps(trimStart: TimeInterval) async throws {
        guard let ffprobe = testExecutablePath(named: "ffprobe") else {
            return
        }
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "replay-materialization-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let outputURL = directory.appending(path: "clip.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fragments = try await makeOffsetReplayFragments(startTime: 190_000, duration: 2)
        let segmentURLs = try fragments.segments.enumerated().map { index, data in
            let url = directory.appending(path: "segment-\(index).m4s")
            try data.write(to: url)
            return url
        }
        let engine = makeReplayEngine()
        let plan = ReplayBufferClipPlan(
            outputURL: outputURL,
            initializationSegmentData: fragments.initialization,
            segmentFileURLs: segmentURLs,
            segmentIDs: Set(segmentURLs.map(\.lastPathComponent)),
            trimStartOffset: trimStart,
            requestedDuration: 1
        )

        try await engine.materializeClip(plan)

        let probe = try probeTimeline(ffprobe: ffprobe, fileURL: outputURL)
        #expect(abs(probe.startTime) < 0.05)
        #expect(probe.duration > 0.9)
        #expect(probe.duration < 1.1)
    }

    @Test("normalization preserves audio tracks")
    func normalizationPreservesAudioTracks() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "replay-audio-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let outputURL = directory.appending(path: "clip.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try testFixtureURL("input@2x.mp4")
        let engine = makeReplayEngine()
        let plan = ReplayBufferClipPlan(
            outputURL: outputURL,
            initializationSegmentData: try Data(contentsOf: inputURL),
            segmentFileURLs: [],
            segmentIDs: [],
            trimStartOffset: nil,
            requestedDuration: 1
        )

        try await engine.materializeClip(plan)

        let asset = AVURLAsset(url: outputURL)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }
}

private struct ReplayProbeTimeline {
    let startTime: TimeInterval
    let duration: TimeInterval
}

private struct ReplayFragments {
    let initialization: Data
    let segments: [Data]
}

private enum ReplayBufferMaterializationTestError: Error {
    case cannotAddInput
    case cannotCreatePixelBuffer(CVReturn)
    case cannotStartWriting
    case cannotAppendFrame
    case cannotFinishWriting
    case invalidProbeOutput
}

private func makeReplayEngine() -> SegmentedSCStreamReplayEngine {
    SegmentedSCStreamReplayEngine(
        clipDirectoryProvider: { FileManager.default.temporaryDirectory }
    )
}

private func probeTimeline(ffprobe: String, fileURL: URL) throws -> ReplayProbeTimeline {
    let result = try runTestFFProbe(executable: ffprobe, fileURL: fileURL)
    guard result.terminationStatus == 0,
          let data = result.output.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let format = object["format"] as? [String: Any],
          let startText = format["start_time"] as? String,
          let durationText = format["duration"] as? String,
          let startTime = TimeInterval(startText),
          let duration = TimeInterval(durationText)
    else {
        throw ReplayBufferMaterializationTestError.invalidProbeOutput
    }
    return ReplayProbeTimeline(startTime: startTime, duration: duration)
}

private func makeOffsetReplayFragments(
    startTime: TimeInterval,
    duration: TimeInterval
) async throws -> ReplayFragments {
    let frameRate: Int32 = 10
    let frameCount = Int(duration * Double(frameRate))
    let collector = ReplaySegmentCollector()
    let writer = AVAssetWriter(contentType: .mpeg4Movie)
    writer.outputFileTypeProfile = .mpeg4AppleHLS
    writer.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
    writer.initialSegmentStartTime = CMTime(seconds: startTime, preferredTimescale: 600)
    writer.delegate = collector
    let input = makeReplayVideoInput()
    let adaptor = makeReplayPixelBufferAdaptor(input: input)
    guard writer.canAdd(input) else {
        throw ReplayBufferMaterializationTestError.cannotAddInput
    }
    writer.add(input)
    guard writer.startWriting() else {
        throw ReplayBufferMaterializationTestError.cannotStartWriting
    }
    writer.startSession(atSourceTime: CMTime(seconds: startTime, preferredTimescale: 600))

    for frameIndex in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        let frameTime = CMTime(
            seconds: startTime + Double(frameIndex) / Double(frameRate),
            preferredTimescale: 600
        )
        guard adaptor.append(try makeReplayPixelBuffer(), withPresentationTime: frameTime) else {
            throw ReplayBufferMaterializationTestError.cannotAppendFrame
        }
    }

    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else {
        throw ReplayBufferMaterializationTestError.cannotFinishWriting
    }
    return try collector.fragments()
}

private func makeReplayVideoInput() -> AVAssetWriterInput {
    AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ]
    )
}

private func makeReplayPixelBufferAdaptor(
    input: AVAssetWriterInput
) -> AVAssetWriterInputPixelBufferAdaptor {
    AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ]
    )
}

private func makeReplayPixelBuffer() throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        64,
        64,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw ReplayBufferMaterializationTestError.cannotCreatePixelBuffer(status)
    }
    return pixelBuffer
}

private final class ReplaySegmentCollector: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var initializationData: Data?
    private var segmentData: [Data] = []

    func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData data: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        lock.withLock {
            switch segmentType {
            case .initialization:
                initializationData = data
            case .separable:
                segmentData.append(data)
            default:
                break
            }
        }
    }

    func fragments() throws -> ReplayFragments {
        try lock.withLock {
            guard let initializationData else {
                throw ReplayBufferMaterializationTestError.cannotFinishWriting
            }
            return ReplayFragments(initialization: initializationData, segments: segmentData)
        }
    }
}
