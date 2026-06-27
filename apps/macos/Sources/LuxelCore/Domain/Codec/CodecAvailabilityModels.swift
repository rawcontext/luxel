public struct CodecAvailability: Codable, Equatable, Sendable {
    public let registeredExternalFormats: Set<ExportFormat>

    public init(registeredExternalFormats: Set<ExportFormat> = []) throws {
        let unsupportedFormats = registeredExternalFormats.filter { !$0.requiresExternalNativeCodec }
        guard unsupportedFormats.isEmpty else {
            throw CodecAvailabilityError.unsupportedExternalFormat(
                unsupportedFormats.sortedForExportMenu().first ?? .mp4
            )
        }

        self.registeredExternalFormats = registeredExternalFormats
    }

    public static let none = CodecAvailability(checkedExternalFormats: [])

    public var availableExportFormats: [ExportFormat] {
        ExportFormat.videoExportMenuFormats.filter { format in
            format.isAppleNativeV1Format || registeredExternalFormats.contains(format)
        }
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

extension Sequence where Element == ExportFormat {
    fileprivate func sortedForExportMenu() -> [ExportFormat] {
        ExportFormat.videoExportMenuFormats.filter { contains($0) }
    }
}
