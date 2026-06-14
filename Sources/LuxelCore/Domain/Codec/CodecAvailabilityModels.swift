public struct CodecAvailability: Codable, Equatable, Sendable {
    public let registeredExternalFormats: Set<ExportFormat>

    public init(registeredExternalFormats: Set<ExportFormat> = []) throws {
        let unsupportedFormats = registeredExternalFormats.filter { !$0.requiresExternalNativeCodec }
        guard unsupportedFormats.isEmpty else {
            throw CodecAvailabilityError.unsupportedExternalFormat(unsupportedFormats.sortedForExportMenu().first ?? .mp4)
        }

        self.registeredExternalFormats = registeredExternalFormats
    }

    public static let none = CodecAvailability(checkedExternalFormats: [])

    public var availableExportFormats: [ExportFormat] {
        ExportFormat.appleNativeV1Formats
            + ExportFormat.externalNativeCodecFormats.filter(registeredExternalFormats.contains)
    }

    public func supports(_ format: ExportFormat) -> Bool {
        availableExportFormats.contains(format)
    }

    private init(checkedExternalFormats: Set<ExportFormat>) {
        registeredExternalFormats = checkedExternalFormats
    }
}

public enum CodecAvailabilityError: Error, Equatable {
    case unsupportedExternalFormat(ExportFormat)
}

private extension Sequence where Element == ExportFormat {
    func sortedForExportMenu() -> [ExportFormat] {
        ExportFormat.appleNativeV1Formats.filter { contains($0) }
            + ExportFormat.externalNativeCodecFormats.filter { contains($0) }
    }
}
