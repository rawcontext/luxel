import Accelerate
import Foundation

final class DeepFilterNetSTFT {
    private let fftSize: Int
    private let hopSize: Int
    private let frequencyBins: Int
    private let window: [Float]
    private let forwardSetup: OpaquePointer
    private let inverseSetup: OpaquePointer

    init(fftSize: Int, hopSize: Int, window: [Float]) {
        self.fftSize = fftSize
        self.hopSize = hopSize
        frequencyBins = fftSize / 2 + 1
        self.window = window
        forwardSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)!
        inverseSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .INVERSE)!
    }

    deinit {
        vDSP_DFT_DestroySetup(forwardSetup)
        vDSP_DFT_DestroySetup(inverseSetup)
    }

    func forward(
        audio: [Float],
        memory: inout [Float]
    ) -> (real: [Float], imaginary: [Float]) {
        let overlapSize = fftSize - hopSize
        let input = memory + audio
        let frameCount = max(0, (input.count - fftSize) / hopSize + 1)
        guard frameCount > 0 else {
            memory = Array(input.suffix(overlapSize))
            return ([], [])
        }

        var real = [Float](repeating: 0, count: frameCount * frequencyBins)
        var imaginary = real
        var windowed = [Float](repeating: 0, count: fftSize)
        var zeroes = windowed
        var outputReal = windowed
        var outputImaginary = windowed

        for frame in 0..<frameCount {
            input.withUnsafeBufferPointer { source in
                vDSP_vmul(
                    source.baseAddress! + frame * hopSize,
                    1,
                    window,
                    1,
                    &windowed,
                    1,
                    vDSP_Length(fftSize)
                )
            }
            vDSP_vclr(&zeroes, 1, vDSP_Length(fftSize))
            vDSP_DFT_Execute(
                forwardSetup,
                windowed,
                zeroes,
                &outputReal,
                &outputImaginary
            )
            let destination = frame * frequencyBins
            for bin in 0..<frequencyBins {
                real[destination + bin] = outputReal[bin]
                imaginary[destination + bin] = outputImaginary[bin]
            }
        }

        let consumed = frameCount * hopSize
        memory = Array(input.suffix(input.count - consumed))
        if memory.count > overlapSize {
            memory = Array(memory.suffix(overlapSize))
        } else if memory.count < overlapSize {
            memory = [Float](repeating: 0, count: overlapSize - memory.count) + memory
        }
        return (real, imaginary)
    }

    func inverse(
        real: [Float],
        imaginary: [Float],
        memory: inout [Float]
    ) -> [Float] {
        let frameCount = real.count / frequencyBins
        guard frameCount > 0 else {
            return []
        }

        var buffers = DeepFilterNetInverseBuffers(
            outputCount: frameCount * hopSize,
            fftSize: fftSize
        )

        for frame in 0..<frameCount {
            inverseFrame(
                frame,
                real: real,
                imaginary: imaginary,
                buffers: &buffers,
                memory: &memory
            )
        }

        return buffers.output
    }

    private func inverseFrame(
        _ frame: Int,
        real: [Float],
        imaginary: [Float],
        buffers: inout DeepFilterNetInverseBuffers,
        memory: inout [Float]
    ) {
        let source = frame * frequencyBins
        for bin in 0..<frequencyBins {
            buffers.fullReal[bin] = real[source + bin]
            buffers.fullImaginary[bin] = imaginary[source + bin]
        }
        for bin in 1..<(fftSize / 2) {
            buffers.fullReal[fftSize - bin] = buffers.fullReal[bin]
            buffers.fullImaginary[fftSize - bin] = -buffers.fullImaginary[bin]
        }
        vDSP_DFT_Execute(
            inverseSetup,
            buffers.fullReal,
            buffers.fullImaginary,
            &buffers.inverseReal,
            &buffers.inverseImaginary
        )

        var scale = 1 / Float(fftSize)
        vDSP_vsmul(
            buffers.inverseReal,
            1,
            &scale,
            &buffers.inverseReal,
            1,
            vDSP_Length(fftSize)
        )
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(
            buffers.inverseReal,
            1,
            window,
            1,
            &windowed,
            1,
            vDSP_Length(fftSize)
        )
        for index in 0..<min(fftSize, memory.count) {
            windowed[index] += memory[index]
        }
        for index in 0..<hopSize {
            buffers.output[frame * hopSize + index] = windowed[index]
        }
        memory = Array(windowed[hopSize..<fftSize])
    }
}

private struct DeepFilterNetInverseBuffers {
    var output: [Float]
    var fullReal: [Float]
    var fullImaginary: [Float]
    var inverseReal: [Float]
    var inverseImaginary: [Float]

    init(outputCount: Int, fftSize: Int) {
        output = [Float](repeating: 0, count: outputCount)
        fullReal = [Float](repeating: 0, count: fftSize)
        fullImaginary = fullReal
        inverseReal = fullReal
        inverseImaginary = fullReal
    }
}
