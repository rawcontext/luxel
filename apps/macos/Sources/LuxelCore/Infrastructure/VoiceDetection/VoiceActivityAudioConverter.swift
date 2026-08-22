@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import os

final class VoiceActivityAudioConverter: @unchecked Sendable {
    static let sampleRate = 16_000.0

    private let targetFormat: AVAudioFormat
    private var sourceFormat: AVAudioFormat?
    private var monoFormat: AVAudioFormat?
    private var channelConverter: AVAudioConverter?
    private var sampleRateConverter: AVAudioConverter?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard buffer.frameLength > 0 else {
            return []
        }

        if buffer.format == targetFormat {
            return try samples(from: buffer)
        }

        try configure(for: buffer.format)
        let monoBuffer: AVAudioPCMBuffer
        if let channelConverter, let monoFormat {
            monoBuffer = try convert(
                buffer,
                using: channelConverter,
                to: monoFormat,
                capacity: buffer.frameLength
            )
        } else {
            monoBuffer = buffer
        }

        guard let sampleRateConverter else {
            return try samples(from: monoBuffer)
        }

        let ratio = targetFormat.sampleRate / monoBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(monoBuffer.frameLength) * ratio)) + 64
        let output = try convert(
            monoBuffer,
            using: sampleRateConverter,
            to: targetFormat,
            capacity: capacity
        )
        return try samples(from: output)
    }

    func reset() {
        channelConverter?.reset()
        sampleRateConverter?.reset()
    }

    private func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat,
        capacity: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw VoiceActivityAudioConversionError.bufferCreationFailed
        }

        let suppliedInput = OSAllocatedUnfairLock(initialState: false)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            let wasSupplied = suppliedInput.withLock { suppliedInput in
                let previousValue = suppliedInput
                suppliedInput = true
                return previousValue
            }
            guard !wasSupplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }

            inputStatus.pointee = .haveData
            return input
        }

        guard status != .error else {
            throw VoiceActivityAudioConversionError.conversionFailed(conversionError)
        }

        return output
    }

    static func copyBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
            ),
            let format = AVAudioFormat(streamDescription: streamDescription)
        else {
            throw VoiceActivityAudioConversionError.sourceFormatUnavailable
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw VoiceActivityAudioConversionError.bufferCreationFailed
        }
        buffer.frameLength = frameCount

        guard frameCount > 0 else {
            return buffer
        }

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw VoiceActivityAudioConversionError.sampleBufferCopyFailed(status)
        }

        return buffer
    }

    private func configure(for format: AVAudioFormat) throws {
        guard sourceFormat != format else {
            return
        }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw VoiceActivityAudioConversionError.sourceFormatUnavailable
        }

        sourceFormat = format
        self.monoFormat = monoFormat

        if format == monoFormat {
            channelConverter = nil
        } else {
            guard let converter = AVAudioConverter(from: format, to: monoFormat) else {
                throw VoiceActivityAudioConversionError.converterCreationFailed
            }
            channelConverter = converter
        }

        if monoFormat.sampleRate == targetFormat.sampleRate {
            sampleRateConverter = nil
        } else {
            guard let converter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
                throw VoiceActivityAudioConversionError.converterCreationFailed
            }
            sampleRateConverter = converter
        }
    }

    private func samples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channel = buffer.floatChannelData?.pointee else {
            throw VoiceActivityAudioConversionError.outputUnavailable
        }

        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}

enum VoiceActivityAudioConversionError: Error {
    case sourceFormatUnavailable
    case bufferCreationFailed
    case converterCreationFailed
    case conversionFailed(Error?)
    case sampleBufferCopyFailed(OSStatus)
    case outputUnavailable
}
