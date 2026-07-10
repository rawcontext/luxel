// Adapted from soniqo/speech-swift v0.0.21 at commit
// 7609977be837a6529bd04300c6b963e735300070 under Apache-2.0.
// Modified to load only explicit bundled resources and process bounded windows.

import Accelerate
import CoreML
import Foundation

public actor DeepFilterNetStudioVoiceEnhancer: StudioVoiceEnhancing {
    public static let sampleRate = 48_000

    private let locator: BundledStudioVoiceModelLocator
    private var network: DeepFilterNetNetwork?
    private var auxiliaryData: DeepFilterNetAuxiliaryData?
    private var streams: [UUID: DeepFilterNetStreamProcessor] = [:]

    public init(locator: BundledStudioVoiceModelLocator) {
        self.locator = locator
    }

    public func enhance(
        _ input: StudioVoiceWindow,
        progress: StudioVoiceProgressHandler?
    ) async throws -> StudioVoiceWindow {
        guard input.sampleRate == Self.sampleRate else {
            throw StudioVoiceModelError.inferenceFailed("Expected 48 kHz PCM.")
        }
        try Task.checkCancellation()

        let processor: DeepFilterNetStreamProcessor
        if input.beginsStream {
            let runtime = try loadRuntimeIfNeeded()
            processor = DeepFilterNetStreamProcessor(
                network: runtime.network,
                auxiliaryData: runtime.auxiliaryData
            )
            streams[input.streamID] = processor
        } else if let existing = streams[input.streamID] {
            processor = existing
        } else {
            throw StudioVoiceModelError.inferenceFailed("Enhancement stream was not initialized.")
        }

        await progress?(0)
        do {
            var samples = try processor.enhance(input.samples)
            if samples.count > input.samples.count {
                samples.removeLast(samples.count - input.samples.count)
            } else if samples.count < input.samples.count {
                samples.append(contentsOf: repeatElement(0, count: input.samples.count - samples.count))
            }

            if input.endsStream {
                streams.removeValue(forKey: input.streamID)
            }
            try Task.checkCancellation()
            await progress?(1)
            return StudioVoiceWindow(
                streamID: input.streamID,
                samples: samples,
                sampleRate: input.sampleRate,
                beginsStream: input.beginsStream,
                endsStream: input.endsStream
            )
        } catch is CancellationError {
            streams.removeValue(forKey: input.streamID)
            throw CancellationError()
        } catch let error as StudioVoiceModelError {
            streams.removeValue(forKey: input.streamID)
            throw error
        } catch {
            streams.removeValue(forKey: input.streamID)
            throw StudioVoiceModelError.inferenceFailed(error.localizedDescription)
        }
    }

    private func loadRuntimeIfNeeded() throws -> (
        network: DeepFilterNetNetwork,
        auxiliaryData: DeepFilterNetAuxiliaryData
    ) {
        if let network, let auxiliaryData {
            return (network, auxiliaryData)
        }

        let resources = try locator.locate()
        let loadedNetwork: DeepFilterNetNetwork
        do {
            loadedNetwork = try DeepFilterNetNetwork(modelURL: resources.modelURL)
        } catch {
            throw StudioVoiceModelError.modelLoadFailed(error.localizedDescription)
        }
        let loadedAuxiliaryData = try DeepFilterNetNPZReader.load(from: resources.auxiliaryDataURL)

        network = loadedNetwork
        auxiliaryData = loadedAuxiliaryData
        return (loadedNetwork, loadedAuxiliaryData)
    }
}

private struct DeepFilterNetConfiguration {
    let fftSize = 960
    let hopSize = 480
    let erbBands = 32
    let dfBins = 96
    let dfOrder = 5
    let dfLookahead = 2
    let sampleRate = 48_000
    let normalizationTimeConstant: Float = 1

    var frequencyBins: Int { fftSize / 2 + 1 }
    var normalizationAlpha: Float {
        exp(-Float(hopSize) / Float(sampleRate) / normalizationTimeConstant)
    }
}

private final class DeepFilterNetNetwork {
    private let model: MLModel

    init(modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    func predict(
        erbFeatures: MLMultiArray,
        spectralFeatures: MLMultiArray
    ) throws -> (erbMask: MLMultiArray, filterCoefficients: MLMultiArray) {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "feat_erb": MLFeatureValue(multiArray: erbFeatures),
            "feat_spec": MLFeatureValue(multiArray: spectralFeatures)
        ])
        let output = try model.prediction(from: input)

        guard let erbMask = output.featureValue(for: "erb_mask")?.multiArrayValue,
              let coefficients = output.featureValue(for: "df_coefs")?.multiArrayValue
        else {
            throw StudioVoiceModelError.inferenceFailed("Core ML output is incomplete.")
        }

        return (erbMask, coefficients)
    }
}

private struct DeepFilterNetAuxiliaryData {
    let erbFilterbank: [Float]
    let inverseERBFilterbank: [Float]
    let window: [Float]
    let meanNormalizationState: [Float]
    let unitNormalizationState: [Float]
}

private enum DeepFilterNetNPZReader {
    static func load(from url: URL) throws -> DeepFilterNetAuxiliaryData {
        let arrays = try read(url: url)
        guard let erbFilterbank = arrays["erb_fb"],
              let inverseERBFilterbank = arrays["erb_inv_fb"],
              let window = arrays["window"],
              let meanNormalizationState = arrays["mean_norm_state"],
              let unitNormalizationState = arrays["unit_norm_state"],
              erbFilterbank.count == 481 * 32,
              inverseERBFilterbank.count == 32 * 481,
              window.count == 960,
              meanNormalizationState.count == 32,
              unitNormalizationState.count == 96
        else {
            throw StudioVoiceModelError.invalidAuxiliaryData
        }

        return DeepFilterNetAuxiliaryData(
            erbFilterbank: erbFilterbank,
            inverseERBFilterbank: inverseERBFilterbank,
            window: window,
            meanNormalizationState: meanNormalizationState,
            unitNormalizationState: unitNormalizationState
        )
    }

    private static func read(url: URL) throws -> [String: [Float]] {
        let data = try Data(contentsOf: url)
        var result: [String: [Float]] = [:]
        var offset = 0

        while offset + 30 <= data.count {
            guard data[offset] == 0x50,
                  data[offset + 1] == 0x4b,
                  data[offset + 2] == 0x03,
                  data[offset + 3] == 0x04
            else {
                break
            }

            var compressedSize = Int(readUInt32(data, at: offset + 18))
            var uncompressedSize = Int(readUInt32(data, at: offset + 22))
            let nameLength = Int(readUInt16(data, at: offset + 26))
            let extraLength = Int(readUInt16(data, at: offset + 28))
            let nameStart = offset + 30
            guard nameStart + nameLength <= data.count else {
                throw StudioVoiceModelError.invalidAuxiliaryData
            }

            var name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLength)),
                encoding: .utf8
            ) ?? ""
            if name.hasSuffix(".npy") {
                name.removeLast(4)
            }

            if compressedSize == 0xffff_ffff || uncompressedSize == 0xffff_ffff {
                let extraStart = nameStart + nameLength
                guard extraLength >= 4, readUInt16(data, at: extraStart) == 0x0001 else {
                    throw StudioVoiceModelError.invalidAuxiliaryData
                }
                var extraOffset = extraStart + 4
                if uncompressedSize == 0xffff_ffff {
                    uncompressedSize = Int(readUInt64(data, at: extraOffset))
                    extraOffset += 8
                }
                if compressedSize == 0xffff_ffff {
                    compressedSize = Int(readUInt64(data, at: extraOffset))
                }
            }

            guard compressedSize == uncompressedSize else {
                throw StudioVoiceModelError.invalidAuxiliaryData
            }
            let payloadStart = nameStart + nameLength + extraLength
            guard payloadStart + uncompressedSize <= data.count,
                  let floats = parseNPY(
                    data,
                    offset: payloadStart,
                    byteCount: uncompressedSize
                  )
            else {
                throw StudioVoiceModelError.invalidAuxiliaryData
            }

            result[name] = floats
            offset = payloadStart + compressedSize
        }

        return result
    }

    private static func parseNPY(
        _ data: Data,
        offset: Int,
        byteCount: Int
    ) -> [Float]? {
        guard byteCount >= 10,
              data[offset] == 0x93,
              data[offset + 1] == 0x4e
        else {
            return nil
        }

        let majorVersion = data[offset + 6]
        let headerLength = majorVersion == 1
            ? Int(readUInt16(data, at: offset + 8))
            : Int(readUInt32(data, at: offset + 8))
        let headerSize = majorVersion == 1 ? 10 : 12
        let floatStart = offset + headerSize + headerLength
        let floatByteCount = byteCount - headerSize - headerLength
        guard floatByteCount >= 0, floatByteCount.isMultiple(of: 4) else {
            return nil
        }

        var floats = [Float](repeating: 0, count: floatByteCount / 4)
        _ = floats.withUnsafeMutableBytes { destination in
            data.copyBytes(
                to: destination,
                from: floatStart..<(floatStart + floatByteCount)
            )
        }
        return floats
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    }
}

private final class DeepFilterNetStreamProcessor {
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
            frequencyBins: configuration.frequencyBins,
            erbBands: configuration.erbBands,
            frameCount: frameCount
        )
        deepFilterNetMeanNormalize(
            &erbFeatures,
            state: &meanNormalizationState,
            alpha: configuration.normalizationAlpha,
            bandCount: configuration.erbBands,
            frameCount: frameCount
        )

        var spectralReal = [Float](
            repeating: 0,
            count: frameCount * configuration.dfBins
        )
        var spectralImaginary = spectralReal
        for frame in 0..<frameCount {
            for bin in 0..<configuration.dfBins {
                spectralReal[frame * configuration.dfBins + bin] =
                    spectrum.real[frame * configuration.frequencyBins + bin]
                spectralImaginary[frame * configuration.dfBins + bin] =
                    spectrum.imaginary[frame * configuration.frequencyBins + bin]
            }
        }
        deepFilterNetUnitNormalize(
            real: &spectralReal,
            imaginary: &spectralImaginary,
            state: &unitNormalizationState,
            alpha: configuration.normalizationAlpha,
            binCount: configuration.dfBins,
            frameCount: frameCount
        )

        let erbInput = try MLMultiArray(
            shape: [1, 1, frameCount as NSNumber, configuration.erbBands as NSNumber],
            dataType: .float32
        )
        erbFeatures.withUnsafeBufferPointer { source in
            erbInput.dataPointer.assumingMemoryBound(to: Float.self).update(
                from: source.baseAddress!,
                count: erbFeatures.count
            )
        }

        let spectralInput = try MLMultiArray(
            shape: [1, 2, frameCount as NSNumber, configuration.dfBins as NSNumber],
            dataType: .float32
        )
        let spectralPointer = spectralInput.dataPointer.assumingMemoryBound(to: Float.self)
        spectralReal.withUnsafeBufferPointer { source in
            spectralPointer.update(from: source.baseAddress!, count: spectralReal.count)
        }
        spectralImaginary.withUnsafeBufferPointer { source in
            (spectralPointer + spectralReal.count).update(
                from: source.baseAddress!,
                count: spectralImaginary.count
            )
        }

        return (erbInput, spectralInput)
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
            erbBands: configuration.erbBands,
            frequencyBins: configuration.frequencyBins,
            frameCount: frameCount
        )
        let filtered = deepFilterNetApplyFiltering(
            real: source.real,
            imaginary: source.imaginary,
            coefficients: coefficients,
            filteredBins: configuration.dfBins,
            order: configuration.dfOrder,
            lookahead: configuration.dfLookahead,
            frameCount: frameCount,
            frequencyBins: configuration.frequencyBins
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

private final class DeepFilterNetSTFT {
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

        var output = [Float](repeating: 0, count: frameCount * hopSize)
        var fullReal = [Float](repeating: 0, count: fftSize)
        var fullImaginary = fullReal
        var inverseReal = fullReal
        var inverseImaginary = fullReal

        for frame in 0..<frameCount {
            let source = frame * frequencyBins
            for bin in 0..<frequencyBins {
                fullReal[bin] = real[source + bin]
                fullImaginary[bin] = imaginary[source + bin]
            }
            for bin in 1..<(fftSize / 2) {
                fullReal[fftSize - bin] = fullReal[bin]
                fullImaginary[fftSize - bin] = -fullImaginary[bin]
            }
            vDSP_DFT_Execute(
                inverseSetup,
                fullReal,
                fullImaginary,
                &inverseReal,
                &inverseImaginary
            )

            var scale = 1 / Float(fftSize)
            vDSP_vsmul(
                inverseReal,
                1,
                &scale,
                &inverseReal,
                1,
                vDSP_Length(fftSize)
            )
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(
                inverseReal,
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
                output[frame * hopSize + index] = windowed[index]
            }
            memory = Array(windowed[hopSize..<fftSize])
        }

        return output
    }
}

private func deepFilterNetERBFeatures(
    real: [Float],
    imaginary: [Float],
    filterbank: [Float],
    frequencyBins: Int,
    erbBands: Int,
    frameCount: Int
) -> [Float] {
    var power = [Float](repeating: 0, count: frameCount * frequencyBins)
    for index in power.indices {
        power[index] = real[index] * real[index] + imaginary[index] * imaginary[index]
    }

    var erb = [Float](repeating: 0, count: frameCount * erbBands)
    vDSP_mmul(
        power,
        1,
        filterbank,
        1,
        &erb,
        1,
        vDSP_Length(frameCount),
        vDSP_Length(erbBands),
        vDSP_Length(frequencyBins)
    )
    var epsilon: Float = 1e-10
    vDSP_vsadd(erb, 1, &epsilon, &erb, 1, vDSP_Length(erb.count))
    var count = Int32(erb.count)
    vvlog10f(&erb, erb, &count)
    var scale: Float = 10
    vDSP_vsmul(erb, 1, &scale, &erb, 1, vDSP_Length(erb.count))
    return erb
}

private func deepFilterNetMeanNormalize(
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

private func deepFilterNetUnitNormalize(
    real: inout [Float],
    imaginary: inout [Float],
    state: inout [Float],
    alpha: Float,
    binCount: Int,
    frameCount: Int
) {
    let update = 1 - alpha
    for frame in 0..<frameCount {
        for bin in 0..<binCount {
            let index = frame * binCount + bin
            let magnitude = hypot(real[index], imaginary[index])
            state[bin] = magnitude * update + state[bin] * alpha
            let normalization = sqrt(max(state[bin], 1e-10))
            real[index] /= normalization
            imaginary[index] /= normalization
        }
    }
}

private func deepFilterNetApplyFiltering(
    real: [Float],
    imaginary: [Float],
    coefficients: [Float],
    filteredBins: Int,
    order: Int,
    lookahead: Int,
    frameCount: Int,
    frequencyBins: Int
) -> (real: [Float], imaginary: [Float]) {
    let padding = order - 1 - lookahead
    var outputReal = [Float](repeating: 0, count: frameCount * filteredBins)
    var outputImaginary = outputReal

    for frame in 0..<frameCount {
        for bin in 0..<filteredBins {
            var realSum: Float = 0
            var imaginarySum: Float = 0
            for tap in 0..<order {
                let sourceFrame = min(max(frame + tap - padding, 0), frameCount - 1)
                let sourceIndex = sourceFrame * frequencyBins + bin
                let coefficientIndex =
                    (frame * filteredBins * order + bin * order + tap) * 2
                let coefficientReal = coefficients[coefficientIndex]
                let coefficientImaginary = coefficients[coefficientIndex + 1]
                realSum += real[sourceIndex] * coefficientReal
                    - imaginary[sourceIndex] * coefficientImaginary
                imaginarySum += imaginary[sourceIndex] * coefficientReal
                    + real[sourceIndex] * coefficientImaginary
            }
            outputReal[frame * filteredBins + bin] = realSum
            outputImaginary[frame * filteredBins + bin] = imaginarySum
        }
    }
    return (outputReal, outputImaginary)
}

private func deepFilterNetApplyERBMask(
    real: inout [Float],
    imaginary: inout [Float],
    mask: [Float],
    inverseFilterbank: [Float],
    erbBands: Int,
    frequencyBins: Int,
    frameCount: Int
) {
    var expandedMask = [Float](repeating: 0, count: frameCount * frequencyBins)
    vDSP_mmul(
        mask,
        1,
        inverseFilterbank,
        1,
        &expandedMask,
        1,
        vDSP_Length(frameCount),
        vDSP_Length(frequencyBins),
        vDSP_Length(erbBands)
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
