import Foundation

public struct CodecAdapterRegistration: Sendable {
    public let format: ExportFormat
    public let exporter: any MediaExporter
    public let sizeEstimator: any ExportSizeEstimator

    public init(
        format: ExportFormat,
        exporter: any MediaExporter,
        sizeEstimator: any ExportSizeEstimator
    ) throws {
        guard format.requiresExternalNativeCodec else {
            throw CodecAdapterRegistryError.unsupportedRegistrationFormat(format)
        }

        self.format = format
        self.exporter = exporter
        self.sizeEstimator = sizeEstimator
    }
}

public struct CodecAdapterRegistry: Sendable {
    public static let empty = CodecAdapterRegistry(
        registrationsByFormat: [:],
        availability: .none
    )

    public let availability: CodecAvailability
    private let registrationsByFormat: [ExportFormat: CodecAdapterRegistration]

    public init(registrations: [CodecAdapterRegistration] = []) throws {
        var registrationsByFormat: [ExportFormat: CodecAdapterRegistration] = [:]

        for registration in registrations {
            guard registrationsByFormat[registration.format] == nil else {
                throw CodecAdapterRegistryError.duplicateExternalFormat(registration.format)
            }

            registrationsByFormat[registration.format] = registration
        }

        self.registrationsByFormat = registrationsByFormat
        availability = try CodecAvailability(registeredExternalFormats: Set(registrationsByFormat.keys))
    }

    public func mediaExporter(nativeExporter: any MediaExporter) -> any MediaExporter {
        RegisteredCodecMediaExporter(
            nativeExporter: nativeExporter,
            externalExporters: Dictionary(
                uniqueKeysWithValues: registrationsByFormat.map { format, registration in
                    (format, registration.exporter)
                }
            )
        )
    }

    public func exportSizeEstimator(nativeEstimator: any ExportSizeEstimator)
    -> any ExportSizeEstimator {
        RegisteredCodecExportSizeEstimator(
            nativeEstimator: nativeEstimator,
            externalEstimators: Dictionary(
                uniqueKeysWithValues: registrationsByFormat.map { format, registration in
                    (format, registration.sizeEstimator)
                }
            )
        )
    }

    private init(
        registrationsByFormat: [ExportFormat: CodecAdapterRegistration],
        availability: CodecAvailability
    ) {
        self.registrationsByFormat = registrationsByFormat
        self.availability = availability
    }
}

public enum CodecAdapterRegistryError: Error, Equatable {
    case unsupportedRegistrationFormat(ExportFormat)
    case duplicateExternalFormat(ExportFormat)
    case unregisteredExternalFormat(ExportFormat)
}

private struct RegisteredCodecMediaExporter: MediaExporter {
    let nativeExporter: any MediaExporter
    let externalExporters: [ExportFormat: any MediaExporter]

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        guard request.format.requiresExternalNativeCodec else {
            return try await nativeExporter.export(input, to: outputFileURL, progress: progress)
        }

        guard let exporter = externalExporters[request.format] else {
            throw CodecAdapterRegistryError.unregisteredExternalFormat(request.format)
        }

        return try await exporter.export(input, to: outputFileURL, progress: progress)
    }
}

private struct RegisteredCodecExportSizeEstimator: ExportSizeEstimator {
    let nativeEstimator: any ExportSizeEstimator
    let externalEstimators: [ExportFormat: any ExportSizeEstimator]

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        guard request.format.requiresExternalNativeCodec else {
            return try await nativeEstimator.estimate(request)
        }

        guard let estimator = externalEstimators[request.format] else {
            throw CodecAdapterRegistryError.unregisteredExternalFormat(request.format)
        }

        return try await estimator.estimate(request)
    }
}
