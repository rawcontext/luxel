import AVFoundation
import Foundation

extension ExportAudioPreparationWorker {
    func renderRawPCM(
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

    func renderMixedPCM(
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

    func renderEnhancedPCM(
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

        try await finishEnhancedPCM(
            buffer: buffer,
            streamIDs: streams,
            didProcessWindow: didProcessWindow,
            previousTail: previousTail,
            writer: writer
        )
        await progress?(1)
    }

    func finishEnhancedPCM(
        buffer: RollingPCMBuffer,
        streamIDs: [UUID],
        didProcessWindow: Bool,
        previousTail: [[Float]]?,
        writer: BoundedPCMWriter
    ) async throws {
        if !didProcessWindow || buffer.frameCount > overlapFrameCount {
            let finalWindow = buffer.prefix(buffer.frameCount)
            let enhanced = try await enhance(
                finalWindow,
                streamIDs: streamIDs,
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
            try await endStreams(streamIDs: streamIDs)
        }
    }

    func enhance(
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

    func endStreams(streamIDs: [UUID]) async throws {
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

    func writeEnhancedWindow(
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
}
