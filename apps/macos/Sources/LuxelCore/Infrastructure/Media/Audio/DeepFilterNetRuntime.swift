import CoreML
import Foundation

struct DeepFilterNetConfiguration {
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

final class DeepFilterNetNetwork {
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

struct DeepFilterNetAuxiliaryData {
    let erbFilterbank: [Float]
    let inverseERBFilterbank: [Float]
    let window: [Float]
    let meanNormalizationState: [Float]
    let unitNormalizationState: [Float]
}
