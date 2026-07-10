import AudioToolbox
import CoreMedia
import Foundation

enum CMSampleBufferAudioLevelSampler {
    static func sample(from sampleBuffer: CMSampleBuffer) -> AudioLevelSample? {
        guard let streamDescription = linearPCMDescription(from: sampleBuffer) else {
            return nil
        }

        let bytesPerSample = Int(streamDescription.mBitsPerChannel / 8)
        guard bytesPerSample > 0 else {
            return nil
        }

        return withAudioBufferList(from: sampleBuffer) { audioBufferList in
            accumulatedSample(
                from: audioBufferList,
                streamDescription: streamDescription,
                bytesPerSample: bytesPerSample
            )
        }
    }

    private static func linearPCMDescription(
        from sampleBuffer: CMSampleBuffer
    ) -> AudioStreamBasicDescription? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
            )?.pointee,
            streamDescription.mFormatID == kAudioFormatLinearPCM,
            (streamDescription.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0
        else {
            return nil
        }

        return streamDescription
    }

    private static func withAudioBufferList<Result>(
        from sampleBuffer: CMSampleBuffer,
        _ body: (UnsafeMutablePointer<AudioBufferList>) -> Result?
    ) -> Result? {
        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, bufferListSize > 0 else {
            return nil
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawBufferList.deallocate()
        }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            return nil
        }

        return body(audioBufferList)
    }

    private static func accumulatedSample(
        from audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription,
        bytesPerSample: Int
    ) -> AudioLevelSample? {
        var accumulator = AudioLevelAccumulator()
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0

        for buffer in buffers {
            guard let data = buffer.mData else {
                continue
            }

            let sampleCount = Int(buffer.mDataByteSize) / bytesPerSample
            if isFloat {
                addFloatingPointSamples(
                    data, sampleCount: sampleCount, bytesPerSample: bytesPerSample, to: &accumulator)
            } else if isSignedInteger {
                addSignedIntegerSamples(
                    data, sampleCount: sampleCount, bytesPerSample: bytesPerSample, to: &accumulator)
            }
        }

        return accumulator.sampleCount == 0 ? nil : accumulator.sample
    }

    private static func addFloatingPointSamples(
        _ data: UnsafeMutableRawPointer,
        sampleCount: Int,
        bytesPerSample: Int,
        to accumulator: inout AudioLevelAccumulator
    ) {
        switch bytesPerSample {
        case MemoryLayout<Float>.size:
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<sampleCount {
                accumulator.add(Double(samples[index]))
            }
        case MemoryLayout<Double>.size:
            let samples = data.assumingMemoryBound(to: Double.self)
            for index in 0..<sampleCount {
                accumulator.add(samples[index])
            }
        default:
            return
        }
    }

    private static func addSignedIntegerSamples(
        _ data: UnsafeMutableRawPointer,
        sampleCount: Int,
        bytesPerSample: Int,
        to accumulator: inout AudioLevelAccumulator
    ) {
        switch bytesPerSample {
        case MemoryLayout<Int16>.size:
            let samples = data.assumingMemoryBound(to: Int16.self)
            for index in 0..<sampleCount {
                accumulator.add(Double(samples[index]) / Double(Int16.max))
            }
        case 3:
            let samples = data.assumingMemoryBound(to: UInt8.self)
            for index in 0..<sampleCount {
                let offset = index * 3
                var value =
                    Int32(samples[offset])
                    | (Int32(samples[offset + 1]) << 8)
                    | (Int32(samples[offset + 2]) << 16)
                if value & 0x80_0000 != 0 {
                    value |= ~0xFF_FFFF
                }
                accumulator.add(Double(value) / 8_388_607)
            }
        case MemoryLayout<Int32>.size:
            let samples = data.assumingMemoryBound(to: Int32.self)
            for index in 0..<sampleCount {
                accumulator.add(Double(samples[index]) / Double(Int32.max))
            }
        default:
            return
        }
    }
}

private struct AudioLevelAccumulator {
    private var sumOfSquares = 0.0
    private var peakValue = 0.0
    private(set) var sampleCount = 0

    mutating func add(_ value: Double) {
        guard value.isFinite else {
            return
        }

        let absoluteValue = min(1, abs(value))
        sumOfSquares += absoluteValue * absoluteValue
        peakValue = max(peakValue, absoluteValue)
        sampleCount += 1
    }

    var sample: AudioLevelSample {
        guard sampleCount > 0 else {
            return .silent
        }

        return AudioLevelSample(
            rms: sqrt(sumOfSquares / Double(sampleCount)),
            peak: peakValue
        )
    }
}
