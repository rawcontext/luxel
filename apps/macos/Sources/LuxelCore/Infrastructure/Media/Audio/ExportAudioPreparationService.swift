import AVFAudio
import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

public struct ExportAudioPreparationService: ExportAudioPreparing, Sendable {
    public static let sampleRate = 48_000
    public static let channelCount = 2

    private let enhancer: any StudioVoiceEnhancing
    private let temporaryRootURL: URL
    private let windowFrameCount: Int
    private let overlapFrameCount: Int

    public init(
        enhancer: any StudioVoiceEnhancing,
        temporaryRootURL: URL = FileManager.default.temporaryDirectory
            .appending(path: "Luxel/StudioVoice", directoryHint: .isDirectory),
        windowDuration: TimeInterval = 45,
        overlapDuration: TimeInterval = 0.5
    ) {
        self.enhancer = enhancer
        self.temporaryRootURL = temporaryRootURL
        windowFrameCount = max(2, Int(windowDuration * Double(Self.sampleRate)))
        overlapFrameCount = max(
            1,
            min(
                Int(overlapDuration * Double(Self.sampleRate)),
                windowFrameCount / 2 - 1
            )
        )
    }

    public func prepareAudio(
        for requests: [ExportRequest],
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet {
        let groups = Dictionary(grouping: requests.indices.filter {
            requests[$0].requiresAudioPreparation
        }) { index in
            AudioPreparationKey(request: requests[index])
        }
        guard !groups.isEmpty else {
            return PreparedExportAudioSet()
        }

        let directoryURL = temporaryRootURL.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let cleanup = PreparedExportAudioSet(
            assetsByRequestIndex: [:],
            directoryURL: directoryURL
        )
        do {
            let worker = ExportAudioPreparationWorker(
                enhancer: enhancer,
                directoryURL: directoryURL,
                windowFrameCount: windowFrameCount,
                overlapFrameCount: overlapFrameCount
            )
            var assetsByRequestIndex: [Int: PreparedAudioAsset] = [:]

            return try await withTaskCancellationHandler {
                for (groupIndex, group) in groups.enumerated() {
                    try Task.checkCancellation()
                    guard let representativeIndex = group.value.first else {
                        continue
                    }
                    let requestIndices = group.value.sorted()
                    let asset = try await worker.prepare(
                        request: requests[representativeIndex],
                        fileStem: "prepared-\(groupIndex)",
                        progress: { value in
                            await progress?(
                                ExportAudioPreparationProgress(
                                    requestIndices: requestIndices,
                                    progress: value
                                )
                            )
                        }
                    )
                    for requestIndex in requestIndices {
                        assetsByRequestIndex[requestIndex] = asset
                    }
                }

                return PreparedExportAudioSet(
                    assetsByRequestIndex: assetsByRequestIndex,
                    directoryURL: directoryURL
                )
            } onCancel: {
                worker.cancel()
                cleanup.removeTemporaryFiles()
            }
        } catch {
            cleanup.removeTemporaryFiles()
            throw error
        }
    }
}

private struct AudioPreparationKey: Hashable {
    struct Track: Hashable {
        let kind: AudioTrackKind
        let volume: Double
        let isMuted: Bool
    }

    let sourceURL: URL
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let tracks: [Track]
    let normalizesPeak: Bool
    let studioVoiceEnabled: Bool

    init(request: ExportRequest) {
        sourceURL = request.inputFileURL.standardizedFileURL
        trimStart = request.timeRange.start
        trimEnd = request.timeRange.end
        tracks = request.audioMix?.tracks.map {
            Track(kind: $0.kind, volume: $0.volume, isMuted: $0.isMuted)
        } ?? []
        normalizesPeak = request.audioMix?.normalizePeak == true
        studioVoiceEnabled = request.shouldApplyStudioVoice
    }
}

private final class ExportAudioPreparationWorker: @unchecked Sendable {
    fileprivate static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(ExportAudioPreparationService.sampleRate),
        channels: AVAudioChannelCount(ExportAudioPreparationService.channelCount),
        interleaved: false
    )!

    private let enhancer: any StudioVoiceEnhancing
    private let directoryURL: URL
    private let windowFrameCount: Int
    private let overlapFrameCount: Int
    private let lock = NSLock()
    private var activeReader: AVAssetReader?

    init(
        enhancer: any StudioVoiceEnhancing,
        directoryURL: URL,
        windowFrameCount: Int,
        overlapFrameCount: Int
    ) {
        self.enhancer = enhancer
        self.directoryURL = directoryURL
        self.windowFrameCount = windowFrameCount
        self.overlapFrameCount = overlapFrameCount
    }

    func cancel() {
        lock.lock()
        let reader = activeReader
        lock.unlock()
        reader?.cancelReading()
    }

    func prepare(
        request: ExportRequest,
        fileStem: String,
        progress: StudioVoiceProgressHandler?
    ) async throws -> PreparedAudioAsset {
        let rawURL = directoryURL.appending(path: "\(fileStem)-raw.caf")
        let outputURL = directoryURL.appending(path: "\(fileStem).caf")

        do {
            let peak = try await renderRawPCM(
                request: request,
                outputURL: rawURL,
                progress: progress
            )
            try Task.checkCancellation()

            let resolvedGains = AudioMixResolutionService(
                analyzer: EmptyAudioPeakAnalyzer()
            ).resolvedGains(
                for: request,
                measuredPeaks: [.system: peak]
            )
            let gain = resolvedGains[.system]
                ?? request.audioMix?.mix(for: .system).gain
                ?? 1
            try applyGain(gain, inputURL: rawURL, outputURL: outputURL)
            try? FileManager.default.removeItem(at: rawURL)
            try Task.checkCancellation()

            return PreparedAudioAsset(
                fileURL: outputURL,
                duration: request.timeRange.duration,
                sampleRate: ExportAudioPreparationService.sampleRate,
                channelCount: ExportAudioPreparationService.channelCount
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}

private extension ExportAudioPreparationWorker {
    private func renderRawPCM(
        request: ExportRequest,
        outputURL: URL,
        progress: StudioVoiceProgressHandler?
    ) async throws -> Double {
        let readerOutput = try await makeReader(request: request)
        let expectedFrames = max(
            1,
            Int((request.timeRange.duration * Double(ExportAudioPreparationService.sampleRate)).rounded())
        )
        let outputFile = try makeAudioFile(forWriting: outputURL)
        let writer = BoundedPCMWriter(outputFile: outputFile)

        guard readerOutput.reader.startReading() else {
            throw ExportAudioPreparationError.sourceReadFailed(
                readerOutput.reader.error?.localizedDescription ?? "Unknown reader failure"
            )
        }
        setActiveReader(readerOutput.reader)
        defer { setActiveReader(nil) }

        if request.shouldApplyStudioVoice {
            try await renderEnhancedPCM(
                reader: readerOutput.reader,
                output: readerOutput.output,
                expectedFrames: expectedFrames,
                writer: writer,
                progress: progress
            )
        } else {
            try await renderMixedPCM(
                reader: readerOutput.reader,
                output: readerOutput.output,
                expectedFrames: expectedFrames,
                writer: writer,
                progress: progress
            )
        }

        try finishReading(readerOutput.reader)
        return writer.peak
    }

    private func renderMixedPCM(
        reader: AVAssetReader,
        output: AVAssetReaderAudioMixOutput,
        expectedFrames: Int,
        writer: BoundedPCMWriter,
        progress: StudioVoiceProgressHandler?
    ) async throws {
        var writtenFrames = 0
        while reader.status == .reading,
              let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            var channels = try channels(from: sampleBuffer)
            let allowedFrames = min(channels[0].count, expectedFrames - writtenFrames)
            channels = channels.map { Array($0.prefix(allowedFrames)) }
            try writer.write(channels)
            writtenFrames += allowedFrames
            await progress?(Double(writtenFrames) / Double(expectedFrames))
        }

        if writtenFrames < expectedFrames {
            try writer.write(silence(frameCount: expectedFrames - writtenFrames))
        }
        await progress?(1)
    }

    private func renderEnhancedPCM(
        reader: AVAssetReader,
        output: AVAssetReaderAudioMixOutput,
        expectedFrames: Int,
        writer: BoundedPCMWriter,
        progress: StudioVoiceProgressHandler?
    ) async throws {
        let buffer = RollingPCMBuffer(channelCount: ExportAudioPreparationService.channelCount)
        let streams = (0..<ExportAudioPreparationService.channelCount).map { _ in UUID() }
        var framesRead = 0
        var processedFrames = 0
        var didProcessWindow = false
        var previousTail: [[Float]]?

        while reader.status == .reading,
              let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            var channels = try channels(from: sampleBuffer)
            let allowedFrames = min(channels[0].count, expectedFrames - framesRead)
            channels = channels.map { Array($0.prefix(allowedFrames)) }
            buffer.append(channels)
            framesRead += allowedFrames

            while buffer.frameCount >= windowFrameCount {
                let window = buffer.prefix(windowFrameCount)
                let enhanced = try await enhance(
                    window,
                    streamIDs: streams,
                    beginsStream: !didProcessWindow,
                    endsStream: false
                )
                previousTail = try writeEnhancedWindow(
                    enhanced,
                    previousTail: previousTail,
                    isFinal: false,
                    writer: writer
                )
                didProcessWindow = true
                buffer.consume(windowFrameCount - overlapFrameCount)
                processedFrames = min(
                    expectedFrames,
                    processedFrames == 0
                        ? windowFrameCount
                        : processedFrames + windowFrameCount - overlapFrameCount
                )
                await progress?(Double(processedFrames) / Double(expectedFrames))
            }
        }

        if framesRead < expectedFrames {
            buffer.append(silence(frameCount: expectedFrames - framesRead))
        }

        if !didProcessWindow || buffer.frameCount > overlapFrameCount {
            let finalWindow = buffer.prefix(buffer.frameCount)
            let enhanced = try await enhance(
                finalWindow,
                streamIDs: streams,
                beginsStream: !didProcessWindow,
                endsStream: true
            )
            _ = try writeEnhancedWindow(
                enhanced,
                previousTail: previousTail,
                isFinal: true,
                writer: writer
            )
        } else if let previousTail {
            try writer.write(previousTail)
            try await endStreams(streamIDs: streams)
        }
        await progress?(1)
    }

    private func enhance(
        _ channels: [[Float]],
        streamIDs: [UUID],
        beginsStream: Bool,
        endsStream: Bool
    ) async throws -> [[Float]] {
        var output: [[Float]] = []
        output.reserveCapacity(channels.count)
        for channel in channels.indices {
            try Task.checkCancellation()
            let enhanced = try await enhancer.enhance(
                StudioVoiceWindow(
                    streamID: streamIDs[channel],
                    samples: channels[channel],
                    sampleRate: ExportAudioPreparationService.sampleRate,
                    beginsStream: beginsStream,
                    endsStream: endsStream
                ),
                progress: nil
            )
            output.append(enhanced.samples)
        }
        return output
    }

    private func endStreams(streamIDs: [UUID]) async throws {
        for streamID in streamIDs {
            _ = try await enhancer.enhance(
                StudioVoiceWindow(
                    streamID: streamID,
                    samples: [],
                    sampleRate: ExportAudioPreparationService.sampleRate,
                    beginsStream: false,
                    endsStream: true
                ),
                progress: nil
            )
        }
    }

    private func writeEnhancedWindow(
        _ channels: [[Float]],
        previousTail: [[Float]]?,
        isFinal: Bool,
        writer: BoundedPCMWriter
    ) throws -> [[Float]]? {
        guard let previousTail else {
            if isFinal {
                try writer.write(channels)
                return nil
            }

            let split = max(0, channels[0].count - overlapFrameCount)
            try writer.write(channels.map { Array($0[..<split]) })
            return channels.map { Array($0[split...]) }
        }

        let overlap = min(
            overlapFrameCount,
            previousTail[0].count,
            channels[0].count
        )
        var crossfade = silence(frameCount: overlap)
        for channel in channels.indices {
            for frame in 0..<overlap {
                let position = Float(frame) / Float(max(overlap - 1, 1))
                crossfade[channel][frame] =
                    previousTail[channel][frame] * cos(position * .pi / 2)
                    + channels[channel][frame] * sin(position * .pi / 2)
            }
        }
        try writer.write(crossfade)

        if isFinal {
            try writer.write(channels.map { Array($0.dropFirst(overlap)) })
            return nil
        }

        let tailStart = max(overlap, channels[0].count - overlapFrameCount)
        try writer.write(channels.map { Array($0[overlap..<tailStart]) })
        return channels.map { Array($0[tailStart...]) }
    }

    private func makeReader(
        request: ExportRequest
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderAudioMixOutput) {
        let asset = AVURLAsset(url: request.inputFileURL)
        let sourceTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !sourceTracks.isEmpty else {
            throw ExportAudioPreparationError.missingAudioTrack
        }

        let sourceTimeRange = CMTimeRange(
            start: CMTime(seconds: request.timeRange.start, preferredTimescale: 60_000),
            duration: CMTime(seconds: request.timeRange.duration, preferredTimescale: 60_000)
        )
        let composition = AVMutableComposition()
        let tracks = try sourceTracks.map { sourceTrack in
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportAudioPreparationError.unsupportedAudioLayout
            }
            try track.insertTimeRange(sourceTimeRange, of: sourceTrack, at: .zero)
            return track
        }

        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: ExportAudioPreparationService.sampleRate,
                AVNumberOfChannelsKey: ExportAudioPreparationService.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true
            ]
        )
        guard reader.canAdd(output) else {
            throw ExportAudioPreparationError.sourceReadFailed(
                "AVAssetReader could not add the audio output."
            )
        }
        reader.add(output)
        return (reader, output)
    }

    private func channels(from sampleBuffer: CMSampleBuffer) throws -> [[Float]] {
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: Self.format,
            frameCapacity: frameCount
        ) else {
            throw ExportAudioPreparationError.sourceReadFailed(
                "Could not allocate an audio buffer."
            )
        }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr, let channelData = buffer.floatChannelData else {
            throw ExportAudioPreparationError.sourceReadFailed(
                "Could not copy PCM data (\(status))."
            )
        }

        return (0..<ExportAudioPreparationService.channelCount).map { channel in
            Array(UnsafeBufferPointer(start: channelData[channel], count: Int(frameCount)))
        }
    }

    private func applyGain(
        _ gain: Double,
        inputURL: URL,
        outputURL: URL
    ) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let outputFile = try makeAudioFile(forWriting: outputURL)
        let capacity: AVAudioFrameCount = 4_096
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: Self.format,
            frameCapacity: capacity
        ) else {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }

        while inputFile.framePosition < inputFile.length {
            try Task.checkCancellation()
            try inputFile.read(into: buffer, frameCount: capacity)
            guard let channelData = buffer.floatChannelData else {
                throw ExportAudioPreparationError.preparedAudioWriteFailed
            }
            for channel in 0..<ExportAudioPreparationService.channelCount {
                for frame in 0..<Int(buffer.frameLength) {
                    let scaled = Double(channelData[channel][frame]) * gain
                    channelData[channel][frame] = scaled.isFinite
                        ? Float(min(max(scaled, -1), 1))
                        : 0
                }
            }
            try outputFile.write(from: buffer)
        }
    }

    private func makeAudioFile(forWriting url: URL) throws -> AVAudioFile {
        try? FileManager.default.removeItem(at: url)
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: ExportAudioPreparationService.sampleRate,
                    AVNumberOfChannelsKey: ExportAudioPreparationService.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }
    }

    private func finishReading(_ reader: AVAssetReader) throws {
        switch reader.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw ExportAudioPreparationError.sourceReadFailed(
                reader.error?.localizedDescription ?? "Unknown reader failure"
            )
        case .unknown, .reading:
            throw ExportAudioPreparationError.sourceReadFailed(
                "Audio reading did not complete."
            )
        @unknown default:
            throw ExportAudioPreparationError.sourceReadFailed(
                "Audio reading ended in an unknown state."
            )
        }
    }

    private func setActiveReader(_ reader: AVAssetReader?) {
        lock.lock()
        activeReader = reader
        lock.unlock()
    }

    private func silence(frameCount: Int) -> [[Float]] {
        (0..<ExportAudioPreparationService.channelCount).map { _ in
            [Float](repeating: 0, count: frameCount)
        }
    }
}

private final class RollingPCMBuffer {
    private var channels: [[Float]]
    private var startIndex = 0

    init(channelCount: Int) {
        channels = (0..<channelCount).map { _ in [] }
    }

    var frameCount: Int {
        channels[0].count - startIndex
    }

    func append(_ samples: [[Float]]) {
        for channel in channels.indices {
            channels[channel].append(contentsOf: samples[channel])
        }
    }

    func prefix(_ frameCount: Int) -> [[Float]] {
        channels.map { channel in
            Array(channel[startIndex..<(startIndex + frameCount)])
        }
    }

    func consume(_ frameCount: Int) {
        startIndex += min(frameCount, self.frameCount)
        if startIndex >= 65_536 {
            channels = channels.map { Array($0.dropFirst(startIndex)) }
            startIndex = 0
        }
    }
}

private final class BoundedPCMWriter {
    private let outputFile: AVAudioFile
    private(set) var peak = 0.0

    init(outputFile: AVAudioFile) {
        self.outputFile = outputFile
    }

    func write(_ channels: [[Float]]) throws {
        guard let frameCount = channels.first?.count, frameCount > 0 else {
            return
        }
        guard channels.allSatisfy({ $0.count == frameCount }),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: ExportAudioPreparationWorker.format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let channelData = buffer.floatChannelData
        else {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        for channel in channels.indices {
            for frame in 0..<frameCount {
                let sample = channels[channel][frame].isFinite ? channels[channel][frame] : 0
                channelData[channel][frame] = sample
                peak = max(peak, Double(abs(sample)))
            }
        }
        do {
            try outputFile.write(from: buffer)
        } catch {
            throw ExportAudioPreparationError.preparedAudioWriteFailed
        }
    }
}

private struct EmptyAudioPeakAnalyzer: AudioPeakAnalyzer {
    func measurePeaks(
        _ request: AudioPeakAnalysisRequest
    ) async throws -> [AudioTrackKind: Double] {
        [:]
    }
}

public enum ExportAudioPreparationError: Error, Equatable {
    case preparerUnavailable
    case missingAudioTrack
    case unsupportedAudioLayout
    case sourceReadFailed(String)
    case preparedAudioWriteFailed
}

extension ExportAudioPreparationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .preparerUnavailable:
            LuxelLocalization.string(
                "studioVoice.error.unavailable",
                defaultValue: "This export requires local audio preparation, but it is unavailable."
            )
        case .missingAudioTrack, .unsupportedAudioLayout:
            LuxelLocalization.string(
                "studioVoice.error.audioLayout",
                defaultValue: "Studio Voice could not use this recording's audio layout."
            )
        case .sourceReadFailed:
            LuxelLocalization.string(
                "studioVoice.error.sourceRead",
                defaultValue: "Studio Voice could not read the selected audio."
            )
        case .preparedAudioWriteFailed:
            LuxelLocalization.string(
                "studioVoice.error.write",
                defaultValue: "Studio Voice could not create its temporary export audio."
            )
        }
    }
}
