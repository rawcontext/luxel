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
