import Foundation

extension LocalModelFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog, .unavailableInAppVersion:
            "This model is unavailable in this version of Luxel."
        case .insufficientDiskSpace(let required, let available):
            "The model needs \(Self.bytes(required)) free, but only \(Self.bytes(available)) is available."
        case .networkUnavailable:
            "The model download needs a network connection."
        case .transport:
            "The model download was interrupted. Retry when the connection is stable."
        case .httpStatus(let status):
            "The model server returned HTTP \(status). Retry later or update Luxel if the problem continues."
        case .rateLimited:
            "The model server is temporarily rate limiting downloads. Retry later."
        case .forbiddenRedirect:
            "The model download was redirected to an unapproved server. Update Luxel before retrying."
        case .responseTooLarge, .unexpectedByteCount, .checksumMismatch,
             .invalidFileType, .unexpectedFileSet:
            "The downloaded model did not match Luxel's verified catalog. Retry or update Luxel."
        case .storagePermission:
            "Luxel could not access its local model storage."
        case .storageFailure:
            "Luxel could not write the model to disk. Check free space and retry."
        case .preparationFailed, .validationFailed:
            "The model could not be prepared for offline use. Retry or update Luxel."
        case .installationCorrupt:
            "The installed model needs repair. Re-download it in Settings."
        case .inUse:
            "The model is currently in use. Close active transcription work and retry."
        case .canceled:
            "The model download was canceled."
        case .notInstalled:
            "The model is not installed. Download it in Settings."
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
