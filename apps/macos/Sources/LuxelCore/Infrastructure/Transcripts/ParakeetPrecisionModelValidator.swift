import FluidAudio
import Foundation

public enum FluidAudioOfflinePolicy {
    public static func enable() {
        ModelHub.offlineMode = true
    }
}

public struct ParakeetPrecisionModelValidator: LocalModelValidating {
    public static let validatorKey = LocalModelValidatorKey(
        rawValue: "precision-transcription.parakeet-tdt-v3"
    )
    public static let runtimeDirectoryName = Repo.parakeetV3.folderName
    public let key = Self.validatorKey
    public let version = 1

    public init() {}

    public func prepareAndValidate(
        release: LocalModelRelease,
        stagedPayload: URL,
        preparedOutput: URL
    ) async throws -> LocalModelPreparedPayload {
        FluidAudioOfflinePolicy.enable()
        guard release.runtimeDirectoryName == Self.runtimeDirectoryName else {
            throw LocalModelFailure.invalidCatalog(
                "Precision Transcription runtime directory does not match FluidAudio"
            )
        }
        let runtimeDirectory = preparedOutput.appending(
            path: release.runtimeDirectoryName,
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.copyItem(at: stagedPayload, to: runtimeDirectory)
            guard
                AsrModels.modelsExist(
                    at: runtimeDirectory,
                    version: .v3,
                    encoderPrecision: .int8
                )
            else {
                throw PrecisionTranscriptionError.modelCorrupt
            }
            _ = try await AsrModels.load(
                from: runtimeDirectory,
                version: .v3,
                encoderPrecision: .int8
            )
            return LocalModelPreparedPayload(payloadRoot: preparedOutput)
        } catch is CancellationError {
            throw LocalModelFailure.canceled
        } catch let failure as LocalModelFailure {
            throw failure
        } catch {
            throw LocalModelFailure.validationFailed(
                "Precision Transcription could not load its local files"
            )
        }
    }
}
