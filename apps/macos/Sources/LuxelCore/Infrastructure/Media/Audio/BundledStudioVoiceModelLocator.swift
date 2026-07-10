import CryptoKit
import Foundation

public struct StudioVoiceModelResources: Equatable, Sendable {
    public let directoryURL: URL
    public let modelURL: URL
    public let auxiliaryDataURL: URL
    public let manifest: StudioVoiceModelManifest
}

public struct StudioVoiceModelManifest: Codable, Equatable, Sendable {
    public struct FileEntry: Codable, Equatable, Sendable {
        public let path: String
        public let byteCount: Int
        public let sha256: String
    }

    public let repository: String
    public let revision: String
    public let sourceURL: String
    public let license: String
    public let sampleRate: Int
    public let runtime: String
    public let files: [FileEntry]
}

public struct BundledStudioVoiceModelLocator: Sendable {
    private let modelDirectoryURL: URL?

    public init(modelDirectoryURL: URL?) {
        self.modelDirectoryURL = modelDirectoryURL
    }

    public func locate() throws -> StudioVoiceModelResources {
        guard let directoryURL = modelDirectoryURL else {
            throw StudioVoiceModelError.missingResource("Models/studio-voice")
        }

        let manifestURL = directoryURL.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw StudioVoiceModelError.missingResource("manifest.json")
        }

        let manifest: StudioVoiceModelManifest
        do {
            manifest = try JSONDecoder().decode(
                StudioVoiceModelManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw StudioVoiceModelError.invalidManifest
        }

        for entry in manifest.files {
            let fileURL = directoryURL.appending(path: entry.path)
            guard let data = try? Data(contentsOf: fileURL) else {
                throw StudioVoiceModelError.missingResource(entry.path)
            }
            guard data.count == entry.byteCount else {
                throw StudioVoiceModelError.invalidByteCount(entry.path)
            }

            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256.lowercased() else {
                throw StudioVoiceModelError.checksumMismatch(entry.path)
            }
        }

        let modelURL = directoryURL.appending(
            path: "DeepFilterNet3.mlmodelc",
            directoryHint: .isDirectory
        )
        let auxiliaryDataURL = directoryURL.appending(path: "auxiliary.npz")

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw StudioVoiceModelError.missingResource("DeepFilterNet3.mlmodelc")
        }
        guard FileManager.default.fileExists(atPath: auxiliaryDataURL.path) else {
            throw StudioVoiceModelError.missingResource("auxiliary.npz")
        }

        return StudioVoiceModelResources(
            directoryURL: directoryURL,
            modelURL: modelURL,
            auxiliaryDataURL: auxiliaryDataURL,
            manifest: manifest
        )
    }
}

public enum StudioVoiceModelError: Error, Equatable {
    case missingResource(String)
    case invalidManifest
    case invalidByteCount(String)
    case checksumMismatch(String)
    case modelLoadFailed(String)
    case invalidAuxiliaryData
    case inferenceFailed(String)
}

extension StudioVoiceModelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingResource, .invalidManifest, .invalidByteCount, .checksumMismatch:
            LuxelLocalization.string(
                "studioVoice.error.bundledModel",
                defaultValue: "Studio Voice is missing or damaged. Reinstall or update Luxel, then retry."
            )
        case .modelLoadFailed:
            LuxelLocalization.string(
                "studioVoice.error.modelLoad",
                defaultValue: "Studio Voice could not load its local audio model. Retry the export."
            )
        case .invalidAuxiliaryData, .inferenceFailed:
            LuxelLocalization.string(
                "studioVoice.error.processing",
                defaultValue: "Studio Voice could not enhance the exported audio. Retry the export."
            )
        }
    }
}
