import CoreML
import Foundation

final class DeepFilterNetStreamProcessor {
    private let configuration = DeepFilterNetConfiguration()
    private let network: DeepFilterNetNetwork
    private let stft: DeepFilterNetSTFT
    private let erbFilterbank: [Float]
    private let inverseERBFilterbank: [Float]
    private var meanNormalizationState: [Float]
    private var unitNormalizationState: [Float]
    private var analysisMemory: [Float]
    private var synthesisMemory: [Float]

    init(network: DeepFilterNetNetwork, auxiliaryData: DeepFilterNetAuxiliaryData) {
        self.network = network
        stft = DeepFilterNetSTFT(
            fftSize: configuration.fftSize,
            hopSize: configuration.hopSize,
            window: auxiliaryData.window
        )
        erbFilterbank = auxiliaryData.erbFilterbank
        inverseERBFilterbank = auxiliaryData.inverseERBFilterbank
        meanNormalizationState = auxiliaryData.meanNormalizationState
        unitNormalizationState = auxiliaryData.unitNormalizationState
        analysisMemory = [Float](
            repeating: 0,
            count: configuration.fftSize - configuration.hopSize
        )
        synthesisMemory = [Float](
            repeating: 0,
            count: configuration.fftSize - configuration.hopSize
        )
    }

    func enhance(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        let paddedSamples = samples + [Float](repeating: 0, count: configuration.hopSize)
        let spectrum = stft.forward(audio: paddedSamples, memory: &analysisMemory)
        let frameCount = spectrum.real.count / configuration.frequencyBins
        guard frameCount > 0 else {
            return samples
        }

        let inputs = try makeModelInputs(spectrum: spectrum, frameCount: frameCount)
        let prediction = try network.predict(
            erbFeatures: inputs.erb,
            spectralFeatures: inputs.spectral
        )
        let modelOutput = modelOutput(prediction: prediction, frameCount: frameCount)
        let enhanced = enhancedSpectrum(
            source: spectrum,
            erbMask: modelOutput.erbMask,
            coefficients: modelOutput.coefficients,
            frameCount: frameCount
        )
        let output = stft.inverse(
            real: enhanced.real,
            imaginary: enhanced.imaginary,
            memory: &synthesisMemory
        )
        let start = configuration.hopSize
        let end = min(start + samples.count, output.count)
        guard end > start else {
            return []
        }
        return Array(output[start..<end])
    }

    private func makeModelInputs(
        spectrum: (real: [Float], imaginary: [Float]),
        frameCount: Int
    ) throws -> (erb: MLMultiArray, spectral: MLMultiArray) {
        var erbFeatures = deepFilterNetERBFeatures(
            real: spectrum.real,
            imaginary: spectrum.imaginary,
            filterbank: erbFilterbank,
            shape: DeepFilterNetFeatureShape(
                frequencyBins: configuration.frequencyBins,
                erbBands: configuration.erbBands,
                frameCount: frameCount
            )
        )
        deepFilterNetMeanNormalize(
            &erbFeatures,
            state: &meanNormalizationState,
            alpha: configuration.normalizationAlpha,
            bandCount: configuration.erbBands,
            frameCount: frameCount
        )

        let spectralFeatures = normalizedSpectralFeatures(
            spectrum: spectrum,
            frameCount: frameCount
        )
        return (
            try erbInput(features: erbFeatures, frameCount: frameCount),
            try spectralInput(features: spectralFeatures, frameCount: frameCount)
        )
    }

    private func normalizedSpectralFeatures(
        spectrum: (real: [Float], imaginary: [Float]),
        frameCount: Int
    ) -> (real: [Float], imaginary: [Float]) {
        var real = [Float](repeating: 0, count: frameCount * configuration.dfBins)
        var imaginary = real
        for frame in 0..<frameCount {
            for bin in 0..<configuration.dfBins {
                real[frame * configuration.dfBins + bin] =
                    spectrum.real[frame * configuration.frequencyBins + bin]
                imaginary[frame * configuration.dfBins + bin] =
                    spectrum.imaginary[frame * configuration.frequencyBins + bin]
            }
        }
        deepFilterNetUnitNormalize(
            real: &real,
            imaginary: &imaginary,
            state: &unitNormalizationState,
            alpha: configuration.normalizationAlpha,
            shape: DeepFilterNetNormalizationShape(
                binCount: configuration.dfBins,
                frameCount: frameCount
            )
        )
        return (real, imaginary)
    }

    private func erbInput(features: [Float], frameCount: Int) throws -> MLMultiArray {
        let input = try MLMultiArray(
            shape: [1, 1, frameCount as NSNumber, configuration.erbBands as NSNumber],
            dataType: .float32
        )
        features.withUnsafeBufferPointer { source in
            input.dataPointer.assumingMemoryBound(to: Float.self).update(
                from: source.baseAddress!,
                count: features.count
            )
        }
        return input
    }

    private func spectralInput(
        features: (real: [Float], imaginary: [Float]),
        frameCount: Int
    ) throws -> MLMultiArray {
        let input = try MLMultiArray(
            shape: [1, 2, frameCount as NSNumber, configuration.dfBins as NSNumber],
            dataType: .float32
        )
        let pointer = input.dataPointer.assumingMemoryBound(to: Float.self)
        features.real.withUnsafeBufferPointer { source in
            pointer.update(from: source.baseAddress!, count: features.real.count)
        }
        features.imaginary.withUnsafeBufferPointer { source in
            (pointer + features.real.count).update(
                from: source.baseAddress!,
                count: features.imaginary.count
            )
        }
        return input
    }

    private func modelOutput(
        prediction: (erbMask: MLMultiArray, filterCoefficients: MLMultiArray),
        frameCount: Int
    ) -> (erbMask: [Float], coefficients: [Float]) {
        let erbMask = floats(
            from: prediction.erbMask,
            count: frameCount * configuration.erbBands
        )
        let rawCoefficients = floats(
            from: prediction.filterCoefficients,
            count: configuration.dfOrder * frameCount * configuration.dfBins * 2
        )
        var coefficients = [Float](repeating: 0, count: rawCoefficients.count)
        for frame in 0..<frameCount {
            for bin in 0..<configuration.dfBins {
                for order in 0..<configuration.dfOrder {
                    let sourceIndex =
                        ((order * frameCount + frame) * configuration.dfBins + bin) * 2
                    let destinationIndex =
                        ((frame * configuration.dfBins + bin) * configuration.dfOrder + order) * 2
                    coefficients[destinationIndex] = rawCoefficients[sourceIndex]
                    coefficients[destinationIndex + 1] = rawCoefficients[sourceIndex + 1]
                }
            }
        }

        return (erbMask, coefficients)
    }

    private func enhancedSpectrum(
        source: (real: [Float], imaginary: [Float]),
        erbMask: [Float],
        coefficients: [Float],
        frameCount: Int
    ) -> (real: [Float], imaginary: [Float]) {
        var enhancedReal = source.real
        var enhancedImaginary = source.imaginary
        deepFilterNetApplyERBMask(
            real: &enhancedReal,
            imaginary: &enhancedImaginary,
            mask: erbMask,
            inverseFilterbank: inverseERBFilterbank,
            shape: DeepFilterNetMaskShape(
                erbBands: configuration.erbBands,
                frequencyBins: configuration.frequencyBins,
                frameCount: frameCount
            )
        )
        let filtered = deepFilterNetApplyFiltering(
            real: source.real,
            imaginary: source.imaginary,
            coefficients: coefficients,
            shape: DeepFilterNetFilteringShape(
                filteredBins: configuration.dfBins,
                order: configuration.dfOrder,
                lookahead: configuration.dfLookahead,
                frameCount: frameCount,
                frequencyBins: configuration.frequencyBins
            )
        )
        for frame in 0..<frameCount {
            for bin in 0..<configuration.dfBins {
                enhancedReal[frame * configuration.frequencyBins + bin] =
                    filtered.real[frame * configuration.dfBins + bin]
                enhancedImaginary[frame * configuration.frequencyBins + bin] =
                    filtered.imaginary[frame * configuration.dfBins + bin]
            }
        }
        return (enhancedReal, enhancedImaginary)
    }

    private func floats(from array: MLMultiArray, count: Int) -> [Float] {
        if array.dataType == .float16 {
            let source = array.dataPointer.assumingMemoryBound(to: Float16.self)
            return (0..<count).map { Float(source[$0]) }
        }

        let source = array.dataPointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: source, count: count))
    }
}
