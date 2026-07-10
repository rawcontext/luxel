import AVFAudio
import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

extension AVFoundationMediaExporter {
    static let audioProcessingSampleRate = 48_000.0
    static let audioProcessingChannelCount: AVAudioChannelCount = 2

    static var audioProcessingFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audioProcessingSampleRate,
            channels: audioProcessingChannelCount,
            interleaved: false
        )!
    }

    static var audioReaderOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioProcessingSampleRate,
            AVNumberOfChannelsKey: Int(audioProcessingChannelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
    }

    func runAudioOnlyExport(
        context: AVFoundationAudioExportContext,
        progress: MediaExportProgressHandler?
    ) async throws {
        try? FileManager.default.removeItem(at: context.outputFileURL)
        do {
            let runtime = try makeAudioExportRuntime(context)
            try await writeAudio(runtime, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: context.outputFileURL)
            throw error
        }
    }

    func makeAudioExportRuntime(
        _ context: AVFoundationAudioExportContext
    ) throws -> AVFoundationAudioExportRuntime {
        let reader = try AVAssetReader(asset: context.composition)
        reader.timeRange = context.timeRange
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: context.audioTracks,
            audioSettings: Self.audioReaderOutputSettings
        )
        output.audioMix = context.audioMix
        guard reader.canAdd(output) else {
            throw AVFoundationMediaExporterError.cannotCreateAudioReaderOutput
        }
        reader.add(output)
        let outputFile = try AVAudioFile(
            forWriting: context.outputFileURL,
            settings: try audioOutputSettings(for: context.format),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard reader.startReading() else {
            throw AVFoundationMediaExporterError.audioReaderFailed(
                reader.error?.localizedDescription ?? "Unknown reader failure"
            )
        }
        return AVFoundationAudioExportRuntime(
            reader: reader,
            output: output,
            outputFile: outputFile,
            processingFormat: Self.audioProcessingFormat,
            totalDuration: max(context.timeRange.duration.seconds, .leastNonzeroMagnitude)
        )
    }

    func writeAudio(
        _ runtime: AVFoundationAudioExportRuntime,
        progress: MediaExportProgressHandler?
    ) async throws {
        await progress?(0)
        while runtime.reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = runtime.output.copyNextSampleBuffer() else {
                break
            }
            let buffer = try audioPCMBuffer(
                from: sampleBuffer,
                format: runtime.processingFormat
            )
            try runtime.outputFile.write(from: buffer)
            let sampleEnd =
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                + CMSampleBufferGetDuration(sampleBuffer)
            if sampleEnd.isNumeric {
                await progress?(min(max(sampleEnd.seconds / runtime.totalDuration, 0), 0.99))
            }
        }
        switch runtime.reader.status {
        case .completed:
            await progress?(1)
        case .failed:
            throw AVFoundationMediaExporterError.audioReaderFailed(
                runtime.reader.error?.localizedDescription ?? "Unknown reader failure"
            )
        case .cancelled:
            throw CancellationError()
        case .unknown, .reading:
            throw AVFoundationMediaExporterError.audioReaderFailed(
                String(describing: runtime.reader.status)
            )
        @unknown default:
            throw AVFoundationMediaExporterError.audioReaderFailed(
                String(describing: runtime.reader.status)
            )
        }
    }

    func audioOutputSettings(for format: ExportFormat) throws -> [String: Any] {
        switch format {
        case .m4a:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount),
                AVEncoderBitRateKey: 128_000
            ]
        case .alac:
            [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount),
                AVEncoderBitDepthHintKey: 16
            ]
        case .wav, .caf:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .flac:
            [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: Self.audioProcessingSampleRate,
                AVNumberOfChannelsKey: Int(Self.audioProcessingChannelCount)
            ]
        case .mp4, .hevc, .proRes422, .proRes4444, .gif, .webm, .apng, .av1:
            throw AVFoundationExportPlanError.unsupportedFormat(format)
        }
    }

    func audioPCMBuffer(
        from sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AVFoundationMediaExporterError.cannotCreateAudioBuffer
        }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw AVFoundationMediaExporterError.cannotCopyPCMData(status)
        }

        return buffer
    }
}
