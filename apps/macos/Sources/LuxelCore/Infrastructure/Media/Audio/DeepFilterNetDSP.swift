import Accelerate
import Foundation

func deepFilterNetERBFeatures(
    real: [Float],
    imaginary: [Float],
    filterbank: [Float],
    shape: DeepFilterNetFeatureShape
) -> [Float] {
    var power = [Float](repeating: 0, count: shape.frameCount * shape.frequencyBins)
    for index in power.indices {
        power[index] = real[index] * real[index] + imaginary[index] * imaginary[index]
    }

    var erb = [Float](repeating: 0, count: shape.frameCount * shape.erbBands)
    vDSP_mmul(
        power,
        1,
        filterbank,
        1,
        &erb,
        1,
        vDSP_Length(shape.frameCount),
        vDSP_Length(shape.erbBands),
        vDSP_Length(shape.frequencyBins)
    )
    var epsilon: Float = 1e-10
    vDSP_vsadd(erb, 1, &epsilon, &erb, 1, vDSP_Length(erb.count))
    var count = Int32(erb.count)
    vvlog10f(&erb, erb, &count)
    var scale: Float = 10
    vDSP_vsmul(erb, 1, &scale, &erb, 1, vDSP_Length(erb.count))
    return erb
}

func deepFilterNetMeanNormalize(
    _ values: inout [Float],
    state: inout [Float],
    alpha: Float,
    bandCount: Int,
    frameCount: Int
) {
    let update = 1 - alpha
    for frame in 0..<frameCount {
        for band in 0..<bandCount {
            let index = frame * bandCount + band
            state[band] = values[index] * update + state[band] * alpha
            values[index] = (values[index] - state[band]) / 40
        }
    }
}

func deepFilterNetUnitNormalize(
    real: inout [Float],
    imaginary: inout [Float],
    state: inout [Float],
    alpha: Float,
    shape: DeepFilterNetNormalizationShape
) {
    let update = 1 - alpha
    for frame in 0..<shape.frameCount {
        for bin in 0..<shape.binCount {
            let index = frame * shape.binCount + bin
            let magnitude = hypot(real[index], imaginary[index])
            state[bin] = magnitude * update + state[bin] * alpha
            let normalization = sqrt(max(state[bin], 1e-10))
            real[index] /= normalization
            imaginary[index] /= normalization
        }
    }
}

func deepFilterNetApplyFiltering(
    real: [Float],
    imaginary: [Float],
    coefficients: [Float],
    shape: DeepFilterNetFilteringShape
) -> (real: [Float], imaginary: [Float]) {
    let padding = shape.order - 1 - shape.lookahead
    var outputReal = [Float](repeating: 0, count: shape.frameCount * shape.filteredBins)
    var outputImaginary = outputReal

    for frame in 0..<shape.frameCount {
        for bin in 0..<shape.filteredBins {
            var realSum: Float = 0
            var imaginarySum: Float = 0
            for tap in 0..<shape.order {
                let sourceFrame = frame + tap - padding
                guard sourceFrame >= 0, sourceFrame < shape.frameCount else {
                    continue
                }
                let sourceIndex = sourceFrame * shape.frequencyBins + bin
                let coefficientIndex =
                    (frame * shape.filteredBins * shape.order + bin * shape.order + tap) * 2
                let coefficientReal = coefficients[coefficientIndex]
                let coefficientImaginary = coefficients[coefficientIndex + 1]
                realSum += real[sourceIndex] * coefficientReal
                    - imaginary[sourceIndex] * coefficientImaginary
                imaginarySum += imaginary[sourceIndex] * coefficientReal
                    + real[sourceIndex] * coefficientImaginary
            }
            outputReal[frame * shape.filteredBins + bin] = realSum
            outputImaginary[frame * shape.filteredBins + bin] = imaginarySum
        }
    }
    return (outputReal, outputImaginary)
}

func deepFilterNetApplyERBMask(
    real: inout [Float],
    imaginary: inout [Float],
    mask: [Float],
    inverseFilterbank: [Float],
    shape: DeepFilterNetMaskShape
) {
    var expandedMask = [Float](repeating: 0, count: shape.frameCount * shape.frequencyBins)
    vDSP_mmul(
        mask,
        1,
        inverseFilterbank,
        1,
        &expandedMask,
        1,
        vDSP_Length(shape.frameCount),
        vDSP_Length(shape.frequencyBins),
        vDSP_Length(shape.erbBands)
    )
    vDSP_vmul(real, 1, expandedMask, 1, &real, 1, vDSP_Length(real.count))
    vDSP_vmul(
        imaginary,
        1,
        expandedMask,
        1,
        &imaginary,
        1,
        vDSP_Length(imaginary.count)
    )
}

struct DeepFilterNetFeatureShape {
    let frequencyBins: Int
    let erbBands: Int
    let frameCount: Int
}

struct DeepFilterNetNormalizationShape {
    let binCount: Int
    let frameCount: Int
}

struct DeepFilterNetFilteringShape {
    let filteredBins: Int
    let order: Int
    let lookahead: Int
    let frameCount: Int
    let frequencyBins: Int
}

struct DeepFilterNetMaskShape {
    let erbBands: Int
    let frequencyBins: Int
    let frameCount: Int
}
